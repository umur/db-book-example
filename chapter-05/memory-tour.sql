-- Chapter 5 memory tour.
-- Run top to bottom against a freshly seeded cinetrack database.
-- Each numbered section maps to a moment in the chapter prose.

-- (1) The three settings that govern memory in this chapter.
SHOW shared_buffers;
SHOW work_mem;
SHOW effective_cache_size;
SHOW maintenance_work_mem;

-- (2) The full source-of-truth view of memory-related GUCs.
SELECT name, setting, unit, source
FROM pg_settings
WHERE name IN (
    'shared_buffers',
    'work_mem',
    'maintenance_work_mem',
    'temp_buffers',
    'effective_cache_size',
    'max_connections',
    'huge_pages',
    'wal_buffers'
)
ORDER BY name;

-- (3) The process tree, from inside the database.
--     Each row is one running process. The five long-lived background
--     workers always show up. The rest are client backends.
SELECT pid, backend_type, state, wait_event, query_start
FROM pg_stat_activity
ORDER BY backend_type, pid;

-- (4) Activity right now: what each backend is doing.
SELECT pid, usename, state, wait_event_type, wait_event,
       substring(query, 1, 60) AS query
FROM pg_stat_activity
WHERE backend_type = 'client backend'
ORDER BY backend_start;

-- (5) The bgwriter's history of work.
--     In Postgres 17 this view is narrowly scoped:
--     buffers_clean = pages the bgwriter has written ahead of demand
--     maxwritten_clean = how often the bgwriter stopped early because it hit
--         its per-round write limit (a sign it can't keep up)
--     stats_reset = when the counters were last cleared
--     The old buffers_alloc and buffers_backend columns were removed in PG 17;
--     buffer-allocation and per-backend write counters now live in pg_stat_io.
SELECT buffers_clean, maxwritten_clean, stats_reset
FROM pg_stat_bgwriter;

-- (5b) The checkpointer's history of work.
--     In Postgres 17 the checkpoint counters were split out of pg_stat_bgwriter
--     into a dedicated view. num_timed and num_requested count scheduled and
--     forced checkpoints. write_time and sync_time are the cumulative I/O
--     latencies. buffers_written is the total pages the checkpointer has
--     flushed; restartpoints_* are the standby equivalents.
SELECT num_timed, num_requested,
       restartpoints_timed, restartpoints_req, restartpoints_done,
       write_time, sync_time, buffers_written, stats_reset
FROM pg_stat_checkpointer;

-- (5c) Per-backend I/O attribution. PG 16 introduced pg_stat_io as the
--      proper place to see who is doing reads, writes, and extends.
--      Filter to backend_type = 'client backend' to see foreground writes,
--      which used to be the buffers_backend column on pg_stat_bgwriter.
--      A healthy ratio puts most of the writes in the checkpointer and
--      bgwriter rows, not the client-backend row.
SELECT backend_type, object, context,
       reads, writes, extends, evictions
FROM pg_stat_io
WHERE backend_type IN ('client backend', 'background writer', 'checkpointer')
  AND object = 'relation'
ORDER BY backend_type, context;

-- (6) A query that spills with work_mem = 8MB.
--     The aggregate plus sort over 500k rows does not fit.
EXPLAIN (ANALYZE, BUFFERS)
SELECT user_id, count(*) AS n
FROM view_events
GROUP BY user_id
ORDER BY n DESC;
-- Look for "Sort Method: external merge  Disk: ...kB" in the output.

-- (7) Same query, with work_mem raised for this session only.
SET work_mem = '64MB';

EXPLAIN (ANALYZE, BUFFERS)
SELECT user_id, count(*) AS n
FROM view_events
GROUP BY user_id
ORDER BY n DESC;
-- Now: "Sort Method: quicksort  Memory: ...kB" -- no spill.

-- Reset for the rest of the tour.
RESET work_mem;

-- (8) Spill accounting at the database level.
--     temp_files counts how many temp files the database has created.
--     temp_bytes is the total bytes spilled, ever.
SELECT datname,
       temp_files,
       pg_size_pretty(temp_bytes) AS temp_total,
       blks_read,
       blks_hit,
       round(100.0 * blks_hit / NULLIF(blks_hit + blks_read, 0), 2) AS cache_hit_pct
FROM pg_stat_database
WHERE datname = current_database();

-- (9) Inside shared memory: every named allocation, biggest first.
--     The buffer pool dominates. Locks, procarray, WAL buffers follow.
SELECT name,
       pg_size_pretty(allocated_size) AS size,
       allocated_size
FROM pg_shmem_allocations
ORDER BY allocated_size DESC NULLS LAST
LIMIT 15;

-- (10) The buffer cache by relation. Requires the pg_buffercache extension.
--      Notes:
--      - Filtering on b.reldatabase = current database OID excludes shared
--        catalogs (pg_database, pg_authid, pg_tablespace, ...), which have
--        reldatabase = 0 because they're visible across all databases. Drop
--        the WHERE clause if you want those in the picture too. Shared
--        catalogs are also "mapped relations" whose relfilenode shows as 0
--        in pg_class, so the join hides them either way.
--      - Filtering on b.relforknumber = 0 keeps the count to the main fork
--        (heap data). Forks 1, 2, 3 are the FSM, visibility map, and init
--        fork; useful to see separately, noisy here.
CREATE EXTENSION IF NOT EXISTS pg_buffercache;

SELECT c.relname,
       count(*)                                         AS buffers,
       pg_size_pretty(count(*) * 8192::bigint)          AS cached,
       round(count(*) * 100.0 / (SELECT count(*) FROM pg_buffercache), 2) AS pct_of_cache
FROM pg_buffercache b
JOIN pg_class c ON c.relfilenode = b.relfilenode
WHERE b.reldatabase = (SELECT oid FROM pg_database WHERE datname = current_database())
  AND b.relforknumber = 0
GROUP BY c.relname
ORDER BY buffers DESC
LIMIT 10;

-- (11) Wait events across all live backends.
--      Anything other than NULL means the backend is waiting on something:
--      a lock, a buffer, a network read, the WAL writer, etc.
SELECT pid, state, wait_event_type, wait_event, count(*) OVER () AS total_backends
FROM pg_stat_activity
WHERE backend_type = 'client backend';

-- (12) The connection cost, made visible.
--      Each client backend has a backend_start. Long-lived idle connections
--      are the ones a connection pool would replace.
SELECT pid,
       application_name,
       state,
       backend_start,
       now() - backend_start AS lifetime,
       now() - state_change  AS time_in_state
FROM pg_stat_activity
WHERE backend_type = 'client backend'
ORDER BY backend_start;
