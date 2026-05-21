-- Chapter 23 streaming-replication tour.
-- Run the numbered sections against the indicated host:
--   primary   = localhost:5432
--   standby   = localhost:5433
--   cascade   = localhost:5434
-- Each section maps to a moment in the chapter prose.

\ir init.sql
\ir seed.sql

-- ============================================================
-- (1) On the PRIMARY: who is connected?
--     Three rows expected: standby_1 streaming directly, plus the
--     cascade leaf is invisible here because it streams from the
--     standby, not from the primary.
-- ============================================================
-- psql -h localhost -p 5432 -U cinetrack -d cinetrack
SELECT application_name,
       client_addr,
       state,
       sync_state,
       extract(epoch FROM replay_lag) AS replay_lag_seconds,
       pg_size_pretty(pg_current_wal_lsn() - replay_lsn) AS replay_lag_bytes
FROM pg_stat_replication
ORDER BY application_name;

-- ============================================================
-- (2) On the STANDBY: confirm we are in recovery and how stale we are.
-- ============================================================
-- psql -h localhost -p 5433 -U cinetrack -d cinetrack
SELECT pg_is_in_recovery()                                 AS in_recovery,
       pg_last_wal_receive_lsn()                           AS received,
       pg_last_wal_replay_lsn()                            AS replayed,
       pg_last_xact_replay_timestamp()                     AS last_replay,
       extract(epoch FROM (now() - pg_last_xact_replay_timestamp()))
           AS replay_age_seconds;

-- ============================================================
-- (3) On the STANDBY: what does pg_stat_replication look like here?
--     The standby itself acts as a source for the cascade. The cascade
--     shows up here as "cascade_1".
-- ============================================================
SELECT application_name,
       state,
       sync_state,
       extract(epoch FROM replay_lag) AS replay_lag_seconds
FROM pg_stat_replication;

-- ============================================================
-- (4) On the PRIMARY: produce some write volume so lag is visible.
--     Run this in a separate session to drive a steady WAL stream.
-- ============================================================
-- psql -h localhost -p 5432 -U cinetrack -d cinetrack
INSERT INTO view_events (user_id, movie_id, duration_sec)
SELECT ((g - 1) % 50) + 1,
       ((g * 17) % 100) + 1,
       60 + (g % 1800)
FROM generate_series(1, 100000) AS g;

-- Now re-run section (1) and (2) to see the lag react to the burst.

-- ============================================================
-- (5) On the PRIMARY: confirm the slot inventory.
--     The slot for standby_1 should be active and pinning the WAL the
--     standby still needs.
-- ============================================================
SELECT slot_name,
       slot_type,
       active,
       active_pid,
       pg_size_pretty(pg_current_wal_lsn() - restart_lsn) AS retained_wal
FROM pg_replication_slots
ORDER BY slot_name;

-- ============================================================
-- (6) On the STANDBY: same query, this time the slot is the one that
--     the cascade leaf is using.
-- ============================================================
-- psql -h localhost -p 5433 -U cinetrack -d cinetrack
SELECT slot_name,
       slot_type,
       active,
       active_pid,
       pg_size_pretty(pg_current_wal_lsn() - restart_lsn) AS retained_wal
FROM pg_replication_slots;

-- ============================================================
-- (7) Reproduce a recovery conflict.
--     Open a long-running transaction on the STANDBY:
-- ============================================================
-- psql -h localhost -p 5433 -U cinetrack -d cinetrack
BEGIN;
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SELECT count(*) FROM reviews;
-- Leave this session idle. Do NOT commit yet.
-- (In the two-session demo, leave the transaction open. In this
-- standalone script we roll back so section (8)'s VACUUM can run
-- outside a transaction block.)
ROLLBACK;

-- ============================================================
-- (8) On the PRIMARY: produce dead tuples and vacuum hard.
-- ============================================================
-- psql -h localhost -p 5432 -U cinetrack -d cinetrack
UPDATE reviews
SET body = body || ' (touched)'
WHERE id IN (
    SELECT id FROM reviews ORDER BY random() LIMIT 100
);
VACUUM (VERBOSE, FREEZE) reviews;

-- After a moment, the held transaction in section (7) will be canceled
-- by the standby with:
--   ERROR: canceling statement due to conflict with recovery
--   DETAIL: User query might have needed to see row versions that must be removed.

-- ============================================================
-- (9) Flip hot_standby_feedback on the STANDBY to make conflicts go away.
--     (The compose file already sets it on; this section shows what
--     happens if you turn it off and back on.)
-- ============================================================
-- psql -h localhost -p 5433 -U cinetrack -d cinetrack
ALTER SYSTEM SET hot_standby_feedback = off;
SELECT pg_reload_conf();
-- Repeat sections (7) and (8). The cancel fires within
-- max_standby_streaming_delay (default 30s).

ALTER SYSTEM SET hot_standby_feedback = on;
SELECT pg_reload_conf();
-- Repeat sections (7) and (8). The query now runs to completion.
-- The cost is bloat on the primary while the transaction is open.

-- ============================================================
-- (10) Discover the cascade topology from the PRIMARY and STANDBY.
--      The primary sees only its direct child (standby_1).
--      The standby sees its direct child (cascade_1).
-- ============================================================
-- psql -h localhost -p 5432 -U cinetrack -d cinetrack
SELECT 'primary' AS tier, application_name, state
FROM pg_stat_replication;

-- psql -h localhost -p 5433 -U cinetrack -d cinetrack
SELECT 'standby' AS tier, application_name, state
FROM pg_stat_replication;

-- The cascade leaf is invisible to the primary by construction. To
-- compute end-to-end lag from primary to cascade_1, sum the lag from
-- primary->standby_1 and the lag from standby_1->cascade_1.

-- ============================================================
-- (11) Recovery conflict counters on the STANDBY.
--      The numbers are cumulative since stats reset; alert on growth.
-- ============================================================
-- psql -h localhost -p 5433 -U cinetrack -d cinetrack
SELECT datname,
       confl_tablespace,
       confl_lock,
       confl_snapshot,
       confl_bufferpin,
       confl_deadlock
FROM pg_stat_database_conflicts
WHERE datname = 'cinetrack';
