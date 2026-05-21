-- Chapter 1 queries.
-- Each section maps to a moment in the chapter prose. Run them top to bottom
-- against a freshly seeded cinetrack database.

-- (1) The MVCC peek: every Postgres row has system columns.
--     xmin = inserting transaction id
--     xmax = deleting/updating transaction id (0 if alive)
--     ctid = physical (page, offset) of this row version on disk
SELECT xmin, xmax, ctid, id, user_id, movie_id
FROM reviews
LIMIT 5;

-- (2) Watch an UPDATE create a new physical version.
--     Run inside a transaction so you can see the row before AND after,
--     then commit and look again.
--     NOTE: a small body change can trigger a HOT (Heap-Only Tuple) update,
--     in which case ctid stays the same even though a new tuple was written
--     in the same page. Chapter 6 covers HOT in detail. To force a non-HOT
--     update that moves the tuple to a new page, swap the UPDATE for one
--     that grows the row significantly, e.g.
--         UPDATE reviews SET body = body || repeat(' filler', 200)
--         WHERE id = 1;
BEGIN;
SELECT xmin, xmax, ctid FROM reviews WHERE id = 1;
UPDATE reviews SET body = body || ' (edited)', edited_at = now() WHERE id = 1;
SELECT xmin, xmax, ctid FROM reviews WHERE id = 1;  -- xmin advances; ctid may or may not move (HOT)
COMMIT;

-- (3) Catalog browse: list available extensions on this server.
--     Postgres ships with many; few are loaded by default.
SELECT name, default_version, comment
FROM pg_available_extensions
ORDER BY name
LIMIT 15;

-- (4) Catalog browse: which extensions are actually loaded in this database.
SELECT extname, extversion
FROM pg_extension
ORDER BY extname;

-- (5) The connection census: every backend currently attached to the server.
--     'idle in transaction' is the dangerous state called out in section 1.4.
SELECT pid,
       usename,
       application_name,
       state,
       backend_type,
       backend_start,
       query_start
FROM pg_stat_activity
WHERE backend_type = 'client backend'
ORDER BY query_start;

-- (6) The first EXPLAIN of the book.
--     Top-rated movies of the last 30 years, joined with their rating count.
--     This sets the stage for Part II: read the plan, see seq vs. index scans,
--     watch how the planner picks join methods on a small data set.
EXPLAIN (ANALYZE, BUFFERS)
SELECT m.id, m.title, m.release_year, count(r.*) AS num_ratings, avg(r.score)::numeric(3,1) AS avg_score
FROM movies m
JOIN ratings r ON r.movie_id = m.id
WHERE m.release_year >= 1995
GROUP BY m.id
HAVING count(r.*) >= 3
ORDER BY avg_score DESC, num_ratings DESC
LIMIT 10;

-- (7) Per-table on-disk size, including bloat from MVCC dead tuples.
--     pg_total_relation_size includes indexes, toast, and free space.
SELECT
    relname                                       AS table,
    pg_size_pretty(pg_relation_size(c.oid))       AS heap,
    pg_size_pretty(pg_indexes_size(c.oid))        AS indexes,
    pg_size_pretty(pg_total_relation_size(c.oid)) AS total
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind = 'r'
ORDER BY pg_total_relation_size(c.oid) DESC;

-- (8) The MVCC bloat demonstration.
--     Update the same row 50,000 times. Each UPDATE creates a new tuple
--     version. On a 50-row, short-body table the per-page churn from a
--     thousand updates often hides under the page boundary, so we crank
--     the loop count and pad the body to push tuples past 8 KB pages.
--     Compare table size and dead-tuple count before and after vacuum.
--
--     IMPORTANT: to actually see bloat accumulate, open a SECOND psql
--     session BEFORE running the loop below and run:
--
--         BEGIN;
--         SELECT 1;
--
--     That session pins the visibility horizon and prevents HOT pruning
--     and autovacuum from cleaning dead tuples in real time. Without that
--     pinned snapshot, HOT pruning will keep n_dead_tup low and the demo
--     will look like nothing happened. Once the loop finishes and you
--     have inspected the numbers, COMMIT or ROLLBACK in the second
--     session to release the horizon.
SELECT pg_size_pretty(pg_relation_size('reviews')) AS heap_before;

UPDATE reviews SET body = rpad(body, 200, 'x') WHERE id = 2;  -- pad once, then churn
DO $$
BEGIN
    FOR i IN 1..50000 LOOP
        UPDATE reviews SET body = body WHERE id = 2;
    END LOOP;
END $$;

SELECT pg_size_pretty(pg_relation_size('reviews')) AS heap_after_updates;

-- The dead-tuple count is the cleaner signal. pg_size_pretty rounds to MB
-- and can stay flat even when thousands of dead tuples are present.
SELECT relname, n_live_tup, n_dead_tup
FROM pg_stat_user_tables
WHERE relname = 'reviews';

VACUUM (VERBOSE) reviews;

SELECT pg_size_pretty(pg_relation_size('reviews')) AS heap_after_vacuum;

SELECT relname, n_live_tup, n_dead_tup
FROM pg_stat_user_tables
WHERE relname = 'reviews';

-- (9) Extension diagnostic from section 1.5: which extensions are loaded
--     in this database, and what versions are available on the server.
--     Joins pg_extension (loaded) against pg_available_extensions (installable).
SELECT
  e.extname,
  e.extversion AS installed,
  a.default_version AS available
FROM pg_extension e
JOIN pg_available_extensions a ON a.name = e.extname;
