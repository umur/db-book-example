-- Chapter 18 vacuum tour.
-- Run top to bottom against a freshly seeded cinetrack database with
-- the pgstattuple and pg_visibility extensions enabled.
--
-- Each numbered section maps to a step in section 18.9 of the chapter.
-- Sections (4) and (5) are intentionally aggressive; expect autovacuum log
-- lines in the postgres container output as they run.

-- (1) Baseline: the table before any churn.
ANALYZE reviews;
SELECT relname,
       n_live_tup,
       n_dead_tup,
       n_tup_upd,
       n_tup_hot_upd,
       last_autovacuum,
       autovacuum_count,
       pg_size_pretty(pg_relation_size('reviews')) AS heap_size
FROM pg_stat_user_tables
WHERE relname = 'reviews';

-- (2) Force the bloat. Thirty thousand updates spread across review IDs 1-100.
--     Body and edited_at are unindexed, so updates are HOT-eligible. We disable
--     autovacuum on the table for the duration of the bloat phase so the demo
--     produces visible bloat instead of being cleaned up mid-loop. We also
--     append a real trailing space (not the empty string) so the body actually
--     changes; otherwise HOT pruning may collapse the chain to a no-op.
ALTER TABLE reviews SET (autovacuum_enabled = false);

DO $$
BEGIN
    FOR i IN 1..30000 LOOP
        UPDATE reviews
        SET edited_at = now(),
            body = body || ' '  -- trailing space: forces a real value change
        WHERE id = ((i % 100) + 1);
    END LOOP;
END $$;

ALTER TABLE reviews RESET (autovacuum_enabled);

ANALYZE reviews;

-- (3) Measure the bloat with pg_stat_user_tables.
SELECT relname,
       n_live_tup,
       n_dead_tup,
       round(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 1) AS dead_pct,
       n_tup_upd,
       n_tup_hot_upd,
       round(100.0 * n_tup_hot_upd / NULLIF(n_tup_upd, 0), 1) AS hot_pct,
       autovacuum_count,
       pg_size_pretty(pg_relation_size('reviews')) AS heap_size
FROM pg_stat_user_tables
WHERE relname = 'reviews';
-- hot_pct should be near 100% on a fresh sandbox: body and edited_at are
-- not indexed, so every update is HOT-eligible.

-- (4) Measure the bloat exactly with pgstattuple.
--     This reads every page; on a 50,000-row sandbox that's instant.
--     On a production-sized table, prefer pgstattuple_approx().
SELECT * FROM pgstattuple('reviews');

-- (5) See the visibility map.
SELECT pg_visibility_map_summary('reviews');
SELECT pg_relation_size('reviews') / 8192 AS total_pages;
-- all_visible should be lower right after the churn (vacuum hasn't
-- updated the map yet for the dirtied pages).

-- (6) Reclaim with a manual vacuum and watch dead drop to zero.
VACUUM (VERBOSE, ANALYZE) reviews;

SELECT relname, n_live_tup, n_dead_tup,
       pg_size_pretty(pg_relation_size('reviews')) AS heap_size
FROM pg_stat_user_tables
WHERE relname = 'reviews';
SELECT * FROM pgstattuple('reviews');
-- dead_tuple_percent now near zero. heap_size unchanged: vacuum reclaimed
-- space inside the heap, not back to the OS. To shrink the file itself
-- without downtime, use pg_repack (see README for the docker invocation).
-- For planned-downtime rewriting:
-- VACUUM FULL reviews;  -- ACCESS EXCLUSIVE lock; do not run on production traffic.

-- (7) Apply per-table autovacuum tuning. This is the template from
--     section 18.4, applied to the cinetrack reviews table.
ALTER TABLE reviews SET (
    autovacuum_vacuum_scale_factor = 0.02,
    autovacuum_vacuum_threshold = 500,
    autovacuum_analyze_scale_factor = 0.01,
    autovacuum_vacuum_cost_delay = 2,
    autovacuum_vacuum_cost_limit = 4000,
    fillfactor = 90
);

-- Verify the settings landed.
SELECT relname, reloptions
FROM pg_class
WHERE relname = 'reviews';

-- (8) Re-run the workload with the new settings in place.
--     Watch postgres logs: autovacuum should fire several times during the loop.
DO $$
BEGIN
    FOR i IN 1..30000 LOOP
        UPDATE reviews
        SET edited_at = now(),
            body = body || ' '
        WHERE id = ((i % 100) + 1);
    END LOOP;
END $$;

ANALYZE reviews;
SELECT relname, n_live_tup, n_dead_tup,
       round(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 1) AS dead_pct,
       autovacuum_count, last_autovacuum
FROM pg_stat_user_tables
WHERE relname = 'reviews';
-- autovacuum_count should have incremented, dead_pct should be much lower
-- than after step (3).

-- (9) The autovacuum-lag query. Useful in production to find tables that
--     autovacuum is failing to keep up with.
SELECT relname,
       n_live_tup,
       n_dead_tup,
       round(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 1) AS dead_pct,
       last_autovacuum,
       now() - last_autovacuum AS since_last,
       autovacuum_count
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC NULLS LAST;

-- (10) Wraparound monitoring: per-table relfrozenxid age.
--      The age is tiny on a fresh sandbox, but the query is what you'd
--      run against a production cluster.
SELECT c.relname,
       age(c.relfrozenxid) AS xid_age,
       round(100.0 * age(c.relfrozenxid) / 2000000000, 2) AS pct_of_max,
       pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size
FROM pg_class c
WHERE c.relkind = 'r'
  AND c.relnamespace = 'public'::regnamespace
ORDER BY age(c.relfrozenxid) DESC;

-- (11) Wraparound monitoring at the database level.
--      datfrozenxid is the minimum relfrozenxid across all relations.
--      In production, alert when age(datfrozenxid) exceeds 1,000,000,000.
SELECT datname,
       age(datfrozenxid) AS xid_age,
       round(100.0 * age(datfrozenxid) / 2000000000, 2) AS pct_of_max
FROM pg_database
ORDER BY age(datfrozenxid) DESC;

-- (12) Force a freeze pass on reviews. With FREEZE, vacuum_freeze_min_age
--      is treated as zero: every freezable tuple gets frozen immediately.
--      On a read-mostly table, this also boosts index-only scan performance
--      because the all-frozen visibility-map bit gets set.
VACUUM (FREEZE, VERBOSE, ANALYZE) reviews;

SELECT pg_visibility_map_summary('reviews');
-- all_frozen should now be close to all_visible.

-- (13) Inspect index bloat with pgstatindex.
--      A bloated B-tree has avg_leaf_density < 50% and leaf_fragmentation > 30%.
SELECT * FROM pgstatindex('idx_reviews_movie_id');

-- If the numbers above suggest reindexing:
-- REINDEX INDEX CONCURRENTLY idx_reviews_movie_id;
-- REINDEX TABLE CONCURRENTLY reviews;

-- (14) Long-running transaction detection. The query that finds the session
--      pinning the visibility horizon. Run this in production whenever
--      n_dead_tup keeps climbing despite autovacuum running.
SELECT pid, usename, application_name, state,
       xact_start,
       now() - xact_start AS xact_age,
       backend_xmin,
       age(backend_xmin) AS xmin_age,
       substring(query, 1, 60) AS query
FROM pg_stat_activity
WHERE backend_xmin IS NOT NULL
ORDER BY age(backend_xmin) DESC
LIMIT 5;
-- The session with the largest xmin_age is the one pinning the horizon.
-- If xact_age is hours and the session is 'idle in transaction', that's the
-- one to terminate with pg_terminate_backend(<pid>).
