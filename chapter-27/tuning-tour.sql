-- Chapter 27 tuning tour.
-- Each numbered section demonstrates one tuning knob's effect on a real plan.
-- Run top to bottom against a freshly seeded cinetrack database.

-- (1) The settings the rest of this tour will exercise.
SELECT name, setting, unit, source
FROM pg_settings
WHERE name IN (
    'shared_buffers',
    'work_mem',
    'maintenance_work_mem',
    'effective_cache_size',
    'random_page_cost',
    'seq_page_cost',
    'effective_io_concurrency',
    'max_parallel_workers_per_gather',
    'max_wal_size',
    'checkpoint_timeout'
)
ORDER BY name;

-- (2) random_page_cost = 4.0 (the legacy default).
--     A query that should use idx_view_events_user_id may seq-scan instead,
--     because the planner thinks random reads are 4x more expensive.
SET random_page_cost = 4.0;

EXPLAIN (ANALYZE, BUFFERS)
SELECT user_id, count(*)
FROM view_events
WHERE user_id BETWEEN 100 AND 200
GROUP BY user_id;

-- (3) random_page_cost = 1.1 (NVMe-correct).
--     Now the planner is willing to use the index. Compare the plan shape
--     and the buffers read between (2) and (3).
SET random_page_cost = 1.1;

EXPLAIN (ANALYZE, BUFFERS)
SELECT user_id, count(*)
FROM view_events
WHERE user_id BETWEEN 100 AND 200
GROUP BY user_id;

RESET random_page_cost;

-- (4) effective_cache_size: tell the planner how much memory really exists.
--     A low value (4GB on a 64GB host) makes the planner think index scans
--     will miss cache and prefer sequential scans on large tables.
SET effective_cache_size = '128MB';

EXPLAIN
SELECT m.title, count(v.*) AS views
FROM movies m
JOIN view_events v ON v.movie_id = m.id
WHERE m.release_year BETWEEN 2000 AND 2010
GROUP BY m.title
ORDER BY views DESC
LIMIT 20;

-- (5) Same query, planner told the truth.
SET effective_cache_size = '48GB';

EXPLAIN
SELECT m.title, count(v.*) AS views
FROM movies m
JOIN view_events v ON v.movie_id = m.id
WHERE m.release_year BETWEEN 2000 AND 2010
GROUP BY m.title
ORDER BY views DESC
LIMIT 20;

RESET effective_cache_size;

-- (6) work_mem too low: sort spills to disk.
--     The aggregate over view_events has to sort intermediates. With
--     work_mem = 4MB it spills.
SET work_mem = '4MB';

EXPLAIN (ANALYZE, BUFFERS)
SELECT user_id, count(*) AS n
FROM view_events
GROUP BY user_id
ORDER BY n DESC;
-- Look for: "Sort Method: external merge  Disk: ...kB"

-- (7) work_mem raised: same query stays in memory.
SET work_mem = '64MB';

EXPLAIN (ANALYZE, BUFFERS)
SELECT user_id, count(*) AS n
FROM view_events
GROUP BY user_id
ORDER BY n DESC;
-- Now: "Sort Method: quicksort  Memory: ...kB"

RESET work_mem;

-- (8) Parallelism: max_parallel_workers_per_gather changes plan width.
SET max_parallel_workers_per_gather = 0;

EXPLAIN
SELECT count(*) FROM view_events WHERE duration_sec > 3000;

SET max_parallel_workers_per_gather = 4;

EXPLAIN
SELECT count(*) FROM view_events WHERE duration_sec > 3000;
-- "Gather" with "Workers Planned: 4" appears in the second plan.

RESET max_parallel_workers_per_gather;

-- (9) Cache hit rate: the single most important number on the database.
SELECT datname,
       blks_hit, blks_read,
       round(100.0 * blks_hit / NULLIF(blks_hit + blks_read, 0), 2) AS cache_hit_pct,
       xact_commit, xact_rollback
FROM pg_stat_database
WHERE datname = current_database();

-- (10) The buffer cache by relation. The shape of this output is the
--      truth about your working set. If your hottest tables don't fit in
--      shared_buffers, no amount of work_mem tuning will help.
CREATE EXTENSION IF NOT EXISTS pg_buffercache;

SELECT c.relname,
       count(*)                                AS buffers,
       pg_size_pretty(count(*) * 8192::bigint) AS cached,
       pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size,
       round(count(*) * 8192::bigint * 100.0
             / NULLIF(pg_total_relation_size(c.oid), 0), 2) AS pct_cached
FROM pg_buffercache b
JOIN pg_class c ON c.relfilenode = b.relfilenode
WHERE b.reldatabase = (SELECT oid FROM pg_database WHERE datname = current_database())
GROUP BY c.oid, c.relname
ORDER BY count(*) DESC
LIMIT 10;
