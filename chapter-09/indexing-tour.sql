-- Chapter 9 indexing tour.
-- Run top to bottom against a freshly seeded cinetrack database.
-- Each numbered section maps to a moment in the chapter prose.

-- (1) Baseline plans before any chapter-9 indexes exist.
--     The catalog browse is a sequential scan; review search uses
--     idx_reviews_movie_id but pays a sort step on posted_at.
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title, director, runtime_min
FROM movies
WHERE release_year = 2010 AND director = 'C. Nolan'
ORDER BY id LIMIT 50;

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, body, posted_at
FROM reviews
WHERE movie_id = 17
ORDER BY posted_at DESC
LIMIT 20;

-- (2) Multi-column index, wrong order.
--     (movie_id, user_id) cannot narrow on user_id alone, because
--     user_id is not the leading column. Expect either a Seq Scan on
--     ratings or a full Index Scan over the (movie_id, user_id) tree
--     that re-checks user_id on every entry; neither is what we want.
CREATE INDEX idx_ratings_movie_user ON ratings (movie_id, user_id);

EXPLAIN (ANALYZE, BUFFERS)
SELECT movie_id, score FROM ratings WHERE user_id = 42;

-- (3) Multi-column index, right order.
--     (user_id, movie_id) lets the planner walk straight to user_id = 42.
--     Same query, different plan, two orders of magnitude.
CREATE INDEX idx_ratings_user_movie ON ratings (user_id, movie_id);

EXPLAIN (ANALYZE, BUFFERS)
SELECT movie_id, score FROM ratings WHERE user_id = 42;

-- (4) Equality before range.
--     This index serves WHERE user_id = 42 AND rated_at > ... well
--     because user_id (equality) is first and rated_at (range) is second.
CREATE INDEX idx_ratings_user_rated ON ratings (user_id, rated_at);

EXPLAIN (ANALYZE, BUFFERS)
SELECT movie_id, score FROM ratings
WHERE user_id = 42 AND rated_at > now() - interval '30 days';

-- (5) Partial index on the notifications queue.
--     Tiny on disk, exclusively indexes the pending slice. Watch the
--     plan use it on the dispatcher query.
CREATE INDEX idx_notifications_pending
    ON notifications (created_at)
    WHERE status = 'pending';

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, payload FROM notifications
WHERE status = 'pending'
ORDER BY created_at LIMIT 100;

-- The same index does not help if the query's predicate is broader.
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, payload FROM notifications
WHERE status IN ('pending', 'failed')
ORDER BY created_at LIMIT 100;

-- (6) Expression index on LOWER(email).
--     The seed inserts mixed-case emails. A regular index on email cannot
--     serve LOWER(email) lookups; the expression index does.
EXPLAIN (ANALYZE, BUFFERS)
SELECT id FROM users WHERE LOWER(email) = 'user42@cinetrack.test';
-- Seq Scan, no index on LOWER(email) yet.

CREATE INDEX idx_users_email_lower ON users (LOWER(email));

EXPLAIN (ANALYZE, BUFFERS)
SELECT id FROM users WHERE LOWER(email) = 'user42@cinetrack.test';
-- Index Scan now.

-- (7) Covering index with INCLUDE.
--     Sort by (movie_id, posted_at DESC), include id and body.
--     The query becomes Index Only Scan with Heap Fetches: 0.
--
--     Drop the chapter-2 baseline first. If both indexes coexist, the
--     planner sees two viable choices and often picks the smaller, older
--     one. We want the covering index to win deterministically here.
DROP INDEX IF EXISTS idx_reviews_movie_id;

CREATE INDEX idx_reviews_movie_covering
    ON reviews (movie_id, posted_at DESC)
    INCLUDE (id, body);

VACUUM ANALYZE reviews;  -- ensure visibility map is fresh

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, body, posted_at
FROM reviews
WHERE movie_id = 17
ORDER BY posted_at DESC
LIMIT 20;
-- Look for "Index Only Scan" and "Heap Fetches: 0".

-- (8) Visibility-map degradation.
--     An update breaks all-visible on the affected pages. The same
--     index-only scan now reports nonzero Heap Fetches until vacuum
--     refreshes the map.
UPDATE reviews SET edited_at = now() WHERE movie_id = 17;

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, body, posted_at
FROM reviews
WHERE movie_id = 17
ORDER BY posted_at DESC
LIMIT 20;
-- Heap Fetches > 0.

VACUUM reviews;

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, body, posted_at
FROM reviews
WHERE movie_id = 17
ORDER BY posted_at DESC
LIMIT 20;
-- Heap Fetches: 0 again, assuming no concurrent old-snapshot transactions
-- are holding back the visibility horizon. A long-running transaction in
-- another session can keep VACUUM from re-marking the pages all-visible.

-- (9) Unique constraint as an index.
--     The UNIQUE (user_id, movie_id) on ratings already created a B-tree.
--     pg_indexes shows it; the planner uses it for filters on user_id.
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'ratings';

-- (10) EXCLUDE constraint demo.
--     Insert two non-overlapping bookings: success.
--     Insert an overlapping one: rejected by the GiST exclusion constraint.
INSERT INTO screen_bookings (screen_id, booking) VALUES
    (2, tstzrange('2025-04-15 10:00+00', '2025-04-15 12:00+00', '[)'));
-- Success.

INSERT INTO screen_bookings (screen_id, booking) VALUES
    (2, tstzrange('2025-04-15 11:00+00', '2025-04-15 13:00+00', '[)'));
-- ERROR: conflicting key value violates exclusion constraint.

-- (11) CREATE INDEX CONCURRENTLY.
--     Build an index without blocking writes. Cannot run inside a
--     transaction, so this command must be the only statement in its
--     transaction block. Run it from a fresh psql prompt.
--
--   CREATE INDEX CONCURRENTLY idx_movies_director ON movies (director);
--
-- If the build is interrupted (Ctrl-C, server crash, conflict), Postgres
-- leaves an INVALID index behind. Find them with the query below and
-- drop+recreate.
SELECT
    indexrelid::regclass AS index_name,
    indrelid::regclass   AS table_name
FROM pg_index
WHERE NOT indisvalid;

-- (12) Index audit: which indexes have never been used?
--     Reset stats with SELECT pg_stat_reset(), then come back after a week
--     of representative production traffic. Anything still at idx_scan = 0
--     is a candidate to drop.
SELECT
    schemaname,
    relname           AS table_name,
    indexrelname      AS index_name,
    idx_scan          AS times_used,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
ORDER BY idx_scan ASC, pg_relation_size(indexrelid) DESC;
