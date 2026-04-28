-- Chapter 11 joins tour.
-- Run top to bottom against a freshly seeded cinetrack database.
-- Each numbered section maps to a moment in the chapter prose.

-- (1) Nested loop wins on a small outer side.
--     One user, hundreds of ratings, indexed inner side. The planner
--     picks Nested Loop and the index on idx_ratings_user_id does the
--     real work.
EXPLAIN (ANALYZE, BUFFERS)
SELECT m.title, r.score
FROM users u
JOIN ratings r ON r.user_id = u.id
JOIN movies  m ON m.id      = r.movie_id
WHERE u.username = 'user42';
-- Expect: Nested Loop -> Index Scan on users -> Index Scan on ratings -> Index Scan on movies.

-- (2) Hash join wins on a wide outer side.
--     "All ratings for movies released in 2010" picks up thousands of
--     movies; the hash over movies is built once, ratings are scanned
--     once, and the join is one pass per side.
EXPLAIN (ANALYZE, BUFFERS)
SELECT m.title, count(*) AS rating_count
FROM movies m
JOIN ratings r ON r.movie_id = m.id
WHERE m.release_year = 2010
GROUP BY m.title;
-- Expect: Hash Join with movies on the build side.

-- (3) EXISTS vs IN: same plan, different intent.
--     Both produce a Semi Join. Compare and confirm.
EXPLAIN (ANALYZE, BUFFERS)
SELECT m.id, m.title
FROM movies m
WHERE EXISTS (
    SELECT 1 FROM ratings r WHERE r.movie_id = m.id AND r.score >= 9
);

EXPLAIN (ANALYZE, BUFFERS)
SELECT m.id, m.title
FROM movies m
WHERE m.id IN (
    SELECT r.movie_id FROM ratings r WHERE r.score >= 9
);
-- Expect: both plans use a Hash Semi Join or Nested Loop Semi Join,
-- not a regular join with DISTINCT.

-- (4) The DISTINCT-with-JOIN anti-pattern.
--     Same logical answer as (3), more expensive plan because every
--     match is materialized before deduplication.
EXPLAIN (ANALYZE, BUFFERS)
SELECT DISTINCT m.id, m.title
FROM movies m
JOIN ratings r ON r.movie_id = m.id AND r.score >= 9;
-- Expect: a regular Hash Join with a HashAggregate on top, more buffers
-- than the EXISTS form on (3).

-- (5) LATERAL for top-N-per-group.
--     Five most recent ratings per 2010 movie. With the index on
--     ratings(movie_id), each lateral iteration does a small index
--     lookup. No window function, no extra sort.
CREATE INDEX IF NOT EXISTS idx_ratings_movie_rated
    ON ratings (movie_id, rated_at DESC);

EXPLAIN (ANALYZE, BUFFERS)
SELECT m.id, m.title, r.score, r.rated_at
FROM movies m
JOIN LATERAL (
    SELECT score, rated_at
    FROM ratings
    WHERE movie_id = m.id
    ORDER BY rated_at DESC
    LIMIT 5
) r ON true
WHERE m.release_year = 2010;
-- Expect: Nested Loop with a Limit + Index Scan on the lateral side.

-- (6) CTE optimization fence: the materialized form.
--     The MATERIALIZED keyword forces a fence even though this CTE is
--     only referenced once. The pre-filter on users runs first; the
--     join order downstream is fixed.
EXPLAIN (ANALYZE, BUFFERS)
WITH active_users AS MATERIALIZED (
    SELECT id FROM users
    WHERE last_login_at > now() - interval '7 days'
      AND deleted_at IS NULL
)
SELECT m.title, count(*) AS rating_count
FROM ratings r
JOIN active_users u ON u.id = r.user_id
JOIN movies      m ON m.id = r.movie_id
GROUP BY m.title
ORDER BY rating_count DESC
LIMIT 20;
-- Expect: CTE Scan over a small materialized active_users set,
-- then a Hash Join into ratings, then movies.

-- (7) The same query, inlined.
--     NOT MATERIALIZED lets the planner push the active_users predicate
--     into the join. The plan is different, sometimes faster, sometimes
--     not. Compare buffers and timing against (6).
EXPLAIN (ANALYZE, BUFFERS)
WITH active_users AS NOT MATERIALIZED (
    SELECT id FROM users
    WHERE last_login_at > now() - interval '7 days'
      AND deleted_at IS NULL
)
SELECT m.title, count(*) AS rating_count
FROM ratings r
JOIN active_users u ON u.id = r.user_id
JOIN movies      m ON m.id = r.movie_id
GROUP BY m.title
ORDER BY rating_count DESC
LIMIT 20;

-- (8) Window function: running total of view events per user.
--     PARTITION BY user_id, ORDER BY occurred_at. The default frame is
--     "everything from the start of the partition through the current
--     row," which is exactly the running total.
--     The BETWEEN 1 AND 100 filter narrows the demo so EXPLAIN finishes
--     quickly. Drop it on a small dataset, or widen the range as needed.
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    user_id,
    occurred_at,
    movie_id,
    count(*) OVER (
        PARTITION BY user_id
        ORDER BY occurred_at
    ) AS events_so_far
FROM view_events
WHERE user_id BETWEEN 1 AND 100
ORDER BY user_id, occurred_at;
-- Expect: WindowAgg over an Index Scan on (user_id, occurred_at).
-- The index keeps the input sorted so no explicit Sort is needed.

-- (9) Materialized view for a hot aggregate.
--     "Average score and rating count per movie" is a classic report
--     query. Computing it on every read scans ratings every time.
--     A materialized view holds the result and refreshes on demand.
CREATE MATERIALIZED VIEW IF NOT EXISTS movie_rating_summary AS
SELECT
    m.id,
    m.title,
    m.release_year,
    count(r.id)                AS rating_count,
    avg(r.score)::numeric(4,2) AS avg_score,
    max(r.rated_at)            AS last_rated_at
FROM movies m
LEFT JOIN ratings r ON r.movie_id = m.id
GROUP BY m.id, m.title, m.release_year;

CREATE UNIQUE INDEX IF NOT EXISTS movie_rating_summary_pk
    ON movie_rating_summary (id);

ANALYZE movie_rating_summary;

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title, rating_count, avg_score
FROM movie_rating_summary
WHERE release_year = 2010
ORDER BY rating_count DESC
LIMIT 20;
-- Expect: a single Bitmap Heap Scan or Index Scan over the materialized
-- view, no aggregation, no join. Microseconds vs the seconds the live
-- query spends on the same answer.

-- Refresh story (run when the underlying data changes):
--   REFRESH MATERIALIZED VIEW CONCURRENTLY movie_rating_summary;

-- (10) A query the planner gets wrong.
--      With stale statistics, the planner can pick a Nested Loop where
--      a Hash Join would have been faster. Force the misestimate by
--      inserting fresh rows without ANALYZE, then run the query.
--      Section 10's behavior is sensitive to autovacuum settings. The
--      autoanalyze threshold for ratings on a freshly seeded cinetrack
--      database is around 50,050 rows (50K seed + 10% scale_factor); a
--      50K insert can trip autoanalyze before EXPLAIN runs and erase
--      the misestimate. Either bump the insert to 100K or disable
--      autovacuum for the session: SET autovacuum = off; (this is a
--      session-only override and does not persist).
INSERT INTO ratings (user_id, movie_id, score)
SELECT
    ((g - 1) % 10000) + 1,
    ((g * 23) % 50000) + 1,
    ((g * 5) % 10) + 1
FROM generate_series(1, 50000) AS g;
-- Note: no ANALYZE here. ratings statistics are now stale.

EXPLAIN (ANALYZE, BUFFERS)
SELECT m.title, count(*) AS rating_count
FROM movies m
JOIN ratings r ON r.movie_id = m.id
JOIN users   u ON u.id      = r.user_id
WHERE m.release_year = 2010
  AND u.deleted_at IS NULL
GROUP BY m.title
ORDER BY rating_count DESC
LIMIT 20;
-- Compare the rows= estimates to actual rows. Look for misestimates
-- of 10x or more.

-- (11) Same query, after fixing the statistics.
ANALYZE ratings;

EXPLAIN (ANALYZE, BUFFERS)
SELECT m.title, count(*) AS rating_count
FROM movies m
JOIN ratings r ON r.movie_id = m.id
JOIN users   u ON u.id      = r.user_id
WHERE m.release_year = 2010
  AND u.deleted_at IS NULL
GROUP BY m.title
ORDER BY rating_count DESC
LIMIT 20;
-- Expect: row estimates are now closer to actuals, and the join order
-- (and possibly the join algorithm) flips to the cheaper plan.

-- (12) Pre-join rewrite as the durable fix.
--      Even with good statistics, taking the join order out of the
--      planner's hands by building active movies first is robust to
--      future data drift.
EXPLAIN (ANALYZE, BUFFERS)
WITH movies_2010 AS MATERIALIZED (
    SELECT id, title FROM movies WHERE release_year = 2010
),
active_users AS MATERIALIZED (
    SELECT id FROM users WHERE deleted_at IS NULL
)
SELECT m.title, count(*) AS rating_count
FROM movies_2010 m
JOIN ratings r      ON r.movie_id = m.id
JOIN active_users u ON u.id      = r.user_id
GROUP BY m.title
ORDER BY rating_count DESC
LIMIT 20;
-- Expect: small-set CTEs feed the join, the planner has accurate row
-- counts on each, and the plan is stable across data growth.
