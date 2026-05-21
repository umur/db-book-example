-- Chapter 8 EXPLAIN walkthroughs.
-- Eight queries, each one a misplan that the chapter's diagnostic loop fixes.
-- Run twice with EXPLAIN (ANALYZE, BUFFERS) and compare the second run.
--
-- The "BEFORE" plans below are representative second-run output on warm cache;
-- exact numbers will vary slightly with Postgres version and machine.
-- The "AFTER" plans show the same query after a single targeted fix.

\ir init.sql
\ir seed.sql

\timing on

----------------------------------------------------------------------
-- (1) The prefix-LIKE filter buried under a LIMIT.
----------------------------------------------------------------------

-- Diagnose:
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title, release_year
FROM movies
WHERE release_year >= 2020
  AND title LIKE 'The %'
ORDER BY release_year DESC
LIMIT 20;

-- BEFORE:
--  Limit  (cost=0.42..2891.40 rows=20 width=42) (actual time=12.301..184.221 rows=20 loops=1)
--    Buffers: shared hit=18120 read=204
--    ->  Index Scan Backward using idx_movies_release_year on movies
--          Filter: (title ~~ 'The %'::text)
--          Rows Removed by Filter: 18102
--
-- The index returned 18,000+ rows, the filter discarded most. Add a B-tree
-- with text_pattern_ops so prefix LIKE can be indexed.

CREATE INDEX idx_movies_year_title
    ON movies (release_year DESC, title text_pattern_ops);

ANALYZE movies;

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title, release_year
FROM movies
WHERE release_year >= 2020
  AND title LIKE 'The %'
ORDER BY release_year DESC
LIMIT 20;

-- AFTER:
--  Limit  (cost=0.42..28.10 rows=20 width=42) (actual time=0.082..0.412 rows=20 loops=1)
--    Buffers: shared hit=24
--    ->  Index Scan using idx_movies_year_title on movies
--          Index Cond: ((release_year >= 2020) AND (title >= 'The '::text) AND (title < 'The!'::text))


----------------------------------------------------------------------
-- (2) The user-reviews join that became a Seq Scan.
----------------------------------------------------------------------

EXPLAIN (ANALYZE, BUFFERS)
SELECT r.id, r.body, m.title
FROM reviews r
JOIN movies m ON m.id = r.movie_id
WHERE r.user_id = 12
  AND m.release_year >= 2023;

-- BEFORE: Hash Join driven by Seq Scan on reviews filtered by user_id.
-- 499,900 rows removed by the filter to find user 12's 100 reviews.
-- The reviews table has no user_id index.

CREATE INDEX idx_reviews_user_id ON reviews (user_id);
ANALYZE reviews;

EXPLAIN (ANALYZE, BUFFERS)
SELECT r.id, r.body, m.title
FROM reviews r
JOIN movies m ON m.id = r.movie_id
WHERE r.user_id = 12
  AND m.release_year >= 2023;

-- AFTER: Nested Loop, outer Index Scan on reviews(user_id), inner movies_pkey.


----------------------------------------------------------------------
-- (3) Aggregate that's slow because the work is just big.
----------------------------------------------------------------------

EXPLAIN (ANALYZE, BUFFERS)
SELECT m.id, m.title, count(r.id) AS rating_count, avg(r.score)::numeric(3,1) AS avg_score
FROM movies m
LEFT JOIN ratings r ON r.movie_id = m.id
GROUP BY m.id, m.title
ORDER BY rating_count DESC
LIMIT 100;

-- The plan is fine. Half a million ratings have to be aggregated somehow.
-- No plan-level fix exists. The architecture-level fix is a counter table
-- maintained by triggers, or a refreshed materialized view. EXPLAIN's job
-- here is to tell you the plan is not the problem.


----------------------------------------------------------------------
-- (4) The ORDER BY that triggers a sort spill.
----------------------------------------------------------------------

EXPLAIN (ANALYZE, BUFFERS)
SELECT user_id, score, rated_at
FROM ratings
ORDER BY rated_at DESC, score DESC;

-- BEFORE: Sort Method: external merge  Disk: <NN>kB
-- The sort spills because 500k rows of (user_id, score, rated_at) > work_mem.

-- Two fixes. First option: bump work_mem for this query.
SET LOCAL work_mem = '64MB';

EXPLAIN (ANALYZE, BUFFERS)
SELECT user_id, score, rated_at
FROM ratings
ORDER BY rated_at DESC, score DESC;

-- AFTER: Sort Method: quicksort  Memory: <NN>kB
-- The sort fits, runtime drops sharply. RESET to global default afterwards.
RESET work_mem;

-- Second option: an index on (rated_at DESC, score DESC) for ORDER BY pushdown.
-- Choose based on whether this query is hot enough to deserve an index.


----------------------------------------------------------------------
-- (5) The function that hides selectivity from the planner.
----------------------------------------------------------------------

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title
FROM movies
WHERE lower(title) LIKE 'the q%';

-- BEFORE: Seq Scan on movies, Filter: (lower(title) ~~ 'the q%'::text).
-- The expression lower(title) doesn't match any index; selectivity is a guess.

-- Fix: an expression index on lower(title) with text_pattern_ops.
CREATE INDEX idx_movies_lower_title ON movies (lower(title) text_pattern_ops);
ANALYZE movies;

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title
FROM movies
WHERE lower(title) LIKE 'the q%';

-- AFTER: Index Scan using idx_movies_lower_title on movies
--   Index Cond: ((lower(title) >= 'the q'::text) AND (lower(title) < 'the r'::text))


----------------------------------------------------------------------
-- (6) The nested loop with no index on the inner side.
----------------------------------------------------------------------

EXPLAIN (ANALYZE, BUFFERS)
SELECT m.title, r.score
FROM movies m
JOIN ratings r ON r.movie_id = m.id
WHERE m.director = 'Director 42'
  AND r.score = 10;

-- BEFORE: depending on stats, this can degenerate into a Hash Join with
-- a full scan of ratings, or a Nested Loop with no index on ratings.movie_id
-- being usable because score = 10 isn't selective enough for a separate seek.

-- The fix here depends on what's selective. director is selective; score
-- alone is not. A composite index on ratings(movie_id, score) lets the join
-- find a movie's high scores in one shot.
CREATE INDEX idx_ratings_movie_id_score ON ratings (movie_id, score);
ANALYZE ratings;

EXPLAIN (ANALYZE, BUFFERS)
SELECT m.title, r.score
FROM movies m
JOIN ratings r ON r.movie_id = m.id
WHERE m.director = 'Director 42'
  AND r.score = 10;

-- AFTER: Nested Loop driven by movies(director), inner Index Scan on
-- ratings(movie_id, score). Buffers and runtime both drop.


----------------------------------------------------------------------
-- (7) The Index Only Scan that isn't.
----------------------------------------------------------------------

EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM ratings WHERE movie_id = 7;

-- BEFORE on stale visibility map: Index Scan, not Index Only Scan,
-- because Heap Fetches > 0.
--
-- A fresh VACUUM lets the visibility map mark "all visible" pages.
VACUUM (ANALYZE) ratings;

EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM ratings WHERE movie_id = 7;

-- AFTER: Index Only Scan using idx_ratings_movie_id on ratings
--   Index Cond: (movie_id = 7)
--   Heap Fetches: 0


----------------------------------------------------------------------
-- (8) The correlated subquery that should be a join.
----------------------------------------------------------------------

EXPLAIN (ANALYZE, BUFFERS)
SELECT m.id, m.title,
       (SELECT count(*) FROM ratings r WHERE r.movie_id = m.id) AS n
FROM movies m
WHERE m.release_year = 2023
ORDER BY n DESC
LIMIT 10;

-- BEFORE: the planner runs a SubPlan once per outer row. With a 50k movie
-- table filtered to a year's worth, that's ~900 SubPlan executions.

-- Rewrite as an aggregate join: one pass over ratings, joined back to movies.
EXPLAIN (ANALYZE, BUFFERS)
SELECT m.id, m.title, coalesce(rc.n, 0) AS n
FROM movies m
LEFT JOIN (
    SELECT movie_id, count(*) AS n
    FROM ratings
    GROUP BY movie_id
) rc ON rc.movie_id = m.id
WHERE m.release_year = 2023
ORDER BY n DESC
LIMIT 10;

-- AFTER: one Hash Aggregate over ratings, one Hash Join with movies.
-- Runtime drops by 5-20x depending on data and cache state.


-- End of walkthroughs. Each one follows the chapter's loop:
--   1. EXPLAIN (ANALYZE, BUFFERS) the query.
--   2. Find the slowest node.
--   3. Compare estimated vs. actual rows.
--   4. Decide: stats, index, rewrite, or accept.
--   5. Apply one fix.
--   6. Re-run and confirm.
