-- Chapter 20 monitoring tour.
-- Run top to bottom against a freshly seeded chapter-20 sandbox.
-- Each numbered section maps to a moment in the chapter prose.
-- The tour ends with the home-feed regression walked end to end:
-- catch -> reproduce -> fix -> verify.

-- (1) Top 10 slowest queries by mean execution time.
--     This is the column for "what's slow per call."
--     Reset first so the tour produces clean output.
SELECT pg_stat_statements_reset();

-- Generate some workload so the view has rows. The home-feed query is
-- the regression we'll catch in section (10). Run it 50 times to
-- accumulate stats.
SELECT count(*)
FROM (
    SELECT r.id, r.body, r.posted_at, m.title, u.username
    FROM reviews r
    JOIN movies m ON m.id = r.movie_id
    JOIN users  u ON u.id = r.user_id
    WHERE r.user_id IN (
        SELECT followed_id FROM follows WHERE follower_id = 4271
    )
    ORDER BY r.posted_at DESC
    LIMIT 50
) s;

SELECT
    queryid,
    calls,
    round(mean_exec_time::numeric, 2) AS mean_ms,
    round(total_exec_time::numeric / 1000, 2) AS total_seconds,
    rows,
    left(query, 80) AS query
FROM pg_stat_statements
WHERE query NOT LIKE 'SELECT pg_stat_statements_reset%'
  AND query NOT LIKE '%pg_stat_statements%'
ORDER BY mean_exec_time DESC
LIMIT 10;

-- (2) Top 10 by total time, the "where did the wall time go" view.
SELECT
    queryid,
    calls,
    round(total_exec_time::numeric / 1000, 2) AS total_seconds,
    round(mean_exec_time::numeric, 2)         AS mean_ms,
    left(query, 80)                           AS query
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat_statements%'
ORDER BY total_exec_time DESC
LIMIT 10;

-- (3) pg_stat_activity: what's running right now.
--     Filter to client backends, drop idle connections.
SELECT
    pid,
    usename,
    application_name,
    state,
    wait_event_type,
    wait_event,
    now() - query_start AS runtime,
    left(query, 80)     AS query
FROM pg_stat_activity
WHERE state != 'idle'
  AND backend_type = 'client backend'
ORDER BY query_start;

-- (4) The blockers query.
--     Join pg_stat_activity to itself via pg_blocking_pids to find
--     "who's blocked by whom." On an idle sandbox this returns no rows;
--     induce a blocker by opening a second psql session and running:
--         BEGIN;
--         UPDATE reviews SET body = body WHERE id = 1;
--     Then in a third session:
--         BEGIN;
--         UPDATE reviews SET body = body WHERE id = 1;
--     The third session waits. This query identifies the wait.
SELECT
    blocked.pid              AS blocked_pid,
    blocked.usename          AS blocked_user,
    blocking.pid             AS blocking_pid,
    blocking.usename         AS blocking_user,
    blocking.state           AS blocking_state,
    now() - blocking.query_start AS blocking_runtime,
    left(blocked.query,  80) AS blocked_query,
    left(blocking.query, 80) AS blocking_query
FROM pg_stat_activity blocked
JOIN LATERAL unnest(pg_blocking_pids(blocked.pid)) AS blockers(pid) ON true
JOIN pg_stat_activity blocking ON blocking.pid = blockers.pid
WHERE blocked.wait_event_type = 'Lock';

-- (5) Cache hit ratio. The single most useful long-term health number.
--     Below 95% on a transactional system is a sign shared_buffers is
--     undersized or the working set is bigger than expected.
SELECT
    sum(blks_hit)                                  AS hits,
    sum(blks_read)                                 AS reads,
    round(
        sum(blks_hit)::numeric
        / NULLIF(sum(blks_hit) + sum(blks_read), 0)
        * 100, 2
    )                                              AS hit_ratio_pct
FROM pg_stat_database
WHERE datname = current_database();

-- (6) Replication lag. Anticipate chapters 22-23.
--     Returns no rows on a standalone sandbox; included so the query
--     is in your hands when you need it.
SELECT
    application_name,
    state,
    pg_wal_lsn_diff(pg_current_wal_lsn(), sent_lsn)    AS sent_lag_bytes,
    pg_wal_lsn_diff(pg_current_wal_lsn(), write_lsn)   AS write_lag_bytes,
    pg_wal_lsn_diff(pg_current_wal_lsn(), flush_lsn)   AS flush_lag_bytes,
    pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)  AS replay_lag_bytes
FROM pg_stat_replication;

-- (7) Deadlock count.
--     Cumulative since stats_reset. The metric that matters is the
--     rate, computed from two reads of this view minutes apart.
SELECT
    datname,
    deadlocks,
    stats_reset
FROM pg_stat_database
WHERE datname = current_database();

-- (8) pg_stat_io: per-context I/O visibility (PG 16+).
--     'normal' is the default cache strategy; 'bulkread' is the ring
--     buffer used for sequential scans of large tables; 'vacuum' is
--     the ring buffer autovacuum and explicit VACUUM use.
--     evictions and reuses are populated only for ring-buffer
--     contexts (bulkread, bulkwrite, vacuum); they're NULL for normal.
--     PG 17 adds read_bytes/write_bytes/extend_bytes columns so you
--     don't have to multiply by 8KB; left out here for older-server
--     compatibility.
SELECT
    backend_type,
    object,
    context,
    reads,
    writes,
    extends,
    hits,
    evictions
FROM pg_stat_io
WHERE reads > 0 OR writes > 0
ORDER BY reads DESC
LIMIT 15;

-- (9) The home-feed query (the regression that section 20.8 walks).
--     Capture the plan twice: once before the fix, once after.
EXPLAIN (ANALYZE, BUFFERS)
SELECT r.id, r.body, r.posted_at, m.title, u.username
FROM reviews r
JOIN movies m ON m.id = r.movie_id
JOIN users  u ON u.id = r.user_id
WHERE r.user_id IN (
    SELECT followed_id FROM follows WHERE follower_id = 4271
)
ORDER BY r.posted_at DESC
LIMIT 50;
-- Look for: Hash Semi Join feeding from a Seq Scan on reviews,
-- a Sort with the full result in memory, then LIMIT 50. The bad plan.

-- (10) The fix: a composite index that supports the join + sort.
--      CONCURRENTLY on a real system; the sandbox is small enough
--      that either form is fine.
CREATE INDEX IF NOT EXISTS idx_reviews_user_posted
    ON reviews (user_id, posted_at DESC);

ANALYZE reviews;

-- (11) Re-run the same EXPLAIN. Watch the plan flip to a Nested Loop
--      driven by the followers, with one Index Scan per follower
--      using the new index.
EXPLAIN (ANALYZE, BUFFERS)
SELECT r.id, r.body, r.posted_at, m.title, u.username
FROM reviews r
JOIN movies m ON m.id = r.movie_id
JOIN users  u ON u.id = r.user_id
WHERE r.user_id IN (
    SELECT followed_id FROM follows WHERE follower_id = 4271
)
ORDER BY r.posted_at DESC
LIMIT 50;

-- (12) Verify with pg_stat_statements.
--      Reset, run the query enough times to accumulate stats, then
--      read the view for the new mean_exec_time and hit_pct.
--
--      Important: pg_stat_statements groups rows by query shape per
--      *top-level* statement. Wrapping the workload in a DO block
--      records it as a single PL/pgSQL function call, not 50 SELECTs,
--      and the inner shape never appears in the view. Drive the loop
--      from the client instead. From the host shell:
--
--          for i in $(seq 1 50); do
--            psql -h localhost -U cinetrack -d cinetrack -c "
--              SELECT r.id, r.body, r.posted_at, m.title, u.username
--              FROM reviews r
--              JOIN movies m ON m.id = r.movie_id
--              JOIN users  u ON u.id = r.user_id
--              WHERE r.user_id IN (
--                  SELECT followed_id FROM follows WHERE follower_id = 4271
--              )
--              ORDER BY r.posted_at DESC
--              LIMIT 50;
--            " >/dev/null
--          done
--
--      Or, from inside a psql session, save the query to verify.sql
--      and run `\i verify.sql` followed by `\watch 0.1` (Ctrl+C after
--      ~50 iterations). Either way each execution is its own
--      top-level statement and accumulates a row in the view.
SELECT pg_stat_statements_reset();

-- After driving the workload, read the verify view:
SELECT
    calls,
    round(mean_exec_time::numeric, 2) AS mean_ms,
    round((shared_blks_hit::numeric /
           NULLIF(shared_blks_hit + shared_blks_read, 0)) * 100, 1) AS hit_pct,
    rows / GREATEST(calls, 1) AS rows_per_call
FROM pg_stat_statements
WHERE query LIKE '%SELECT r.id, r.body%'
ORDER BY total_exec_time DESC;

-- (13) Snapshot-diff workflow.
--      The catch step in 20.5 diffs two pg_stat_statements snapshots
--      to find which query *changed*. The pattern, end to end:
--
--      Capture the baseline:
CREATE TEMP TABLE snapshot_a AS
SELECT queryid, calls, total_exec_time, mean_exec_time, query
FROM pg_stat_statements;

--      Run a workload window. In a real system this is whatever
--      traffic happens between two snapshots; here, drive the home
--      feed query a few times from a client loop (see section 12).
--      For a quick demo inside this script we run it directly so the
--      shape lands in the view as a top-level statement.
SELECT count(*)
FROM (
    SELECT r.id, r.body, r.posted_at, m.title, u.username
    FROM reviews r
    JOIN movies m ON m.id = r.movie_id
    JOIN users  u ON u.id = r.user_id
    WHERE r.user_id IN (
        SELECT followed_id FROM follows WHERE follower_id = 4271
    )
    ORDER BY r.posted_at DESC
    LIMIT 50
) s;

--      Capture the after snapshot:
CREATE TEMP TABLE snapshot_b AS
SELECT queryid, calls, total_exec_time, mean_exec_time, query
FROM pg_stat_statements;

--      Diff the two. The top of this list is what changed in the
--      window: the queries that did the most new work.
SELECT
    b.queryid,
    b.calls - COALESCE(a.calls, 0)                          AS new_calls,
    round((b.total_exec_time
           - COALESCE(a.total_exec_time, 0))::numeric, 2)   AS delta_total_ms,
    left(b.query, 80)                                       AS query
FROM snapshot_b b
LEFT JOIN snapshot_a a USING (queryid)
WHERE b.total_exec_time > COALESCE(a.total_exec_time, 0)
ORDER BY (b.total_exec_time - COALESCE(a.total_exec_time, 0)) DESC
LIMIT 10;
