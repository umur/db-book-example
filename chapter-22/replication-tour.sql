-- Chapter 22 replication tour.
-- Run top to bottom against the primary on port 5432. The standby on 5433
-- is up and streaming via the slot named standby_1 created at bootstrap.
-- Each numbered section maps to a moment in the chapter prose.

-- (1) Where the primary is in the WAL right now.
SELECT pg_current_wal_lsn()                  AS current_lsn,
       pg_walfile_name(pg_current_wal_lsn()) AS current_segment;

-- (2) The streaming standby, seen from the primary side.
--     The standby_1 slot was created during pg_basebackup. The connection
--     state, the four LSN columns, and the sync state all live here.
SELECT pid, application_name, client_addr, state,
       sent_lsn, write_lsn, flush_lsn, replay_lsn, sync_state
FROM pg_stat_replication;

-- (3) Replica lag in bytes. Alert on this number, not on seconds.
SELECT application_name,
       pg_current_wal_lsn() - sent_lsn   AS network_lag_bytes,
       pg_current_wal_lsn() - flush_lsn  AS flush_lag_bytes,
       pg_current_wal_lsn() - replay_lsn AS replay_lag_bytes
FROM pg_stat_replication;

-- (4) Create a second physical slot, this time with no consumer attached.
--     We will use it later to demonstrate slot growth.
SELECT pg_create_physical_replication_slot('orphan_demo');

-- (5) The replication-slot inventory. Both slots show up. standby_1 is
--     active because the standby is connected. orphan_demo is inactive
--     because nothing is consuming it.
SELECT slot_name, slot_type, active, restart_lsn,
       pg_current_wal_lsn() - restart_lsn AS bytes_pinned -- (a)
FROM pg_replication_slots
ORDER BY slot_name;
-- (a) bytes_pinned for the active slot stays small because the standby
-- keeps confirming receipt. For the orphan slot it grows with every commit.

-- (6) Generate WAL volume so the orphan slot's pinned bytes grow visibly.
--     Production scenarios pile up gigabytes; on a fresh sandbox you need
--     a few hundred thousand rows before the bytes_pinned number jumps in
--     a satisfying way. The orphan-slot point lands either way.
INSERT INTO view_events (user_id, movie_id, duration_sec)
SELECT ((g - 1) % 25) + 1,
       ((g * 17) % 50) + 1,
       60 + (g % 1800)
FROM generate_series(1, 500000) AS g;

-- (7) Re-check the slot inventory. The orphan slot's pinned bytes have
--     jumped, while standby_1 stays close to zero. This is the disk-fill
--     incident in slow motion.
SELECT slot_name, active,
       pg_size_pretty(pg_current_wal_lsn() - restart_lsn) AS bytes_pinned
FROM pg_replication_slots
ORDER BY slot_name;

-- (8) Create a logical replication slot using the test_decoding output
--     plugin. test_decoding ships with every Postgres build (it lives in
--     contrib) and emits human-readable text, which is what we want for
--     a hands-on inspection demo. pgoutput is what real subscribers use,
--     but its binary protocol isn't meant to be read by eye.
SELECT pg_create_logical_replication_slot('cdc_movies', 'test_decoding');

-- (9) Generate a few row changes the decoder can describe.
INSERT INTO movies (title, release_year, director)
VALUES ('Dune: Part Two', 2024, 'D. Villeneuve');
UPDATE movies SET runtime_min = 166 WHERE title = 'Dune: Part Two';

-- (10) Read decoded changes from the logical slot. Use peek (not get) so
--      the slot doesn't advance and you can run this query repeatedly.
SELECT lsn, xid, data
FROM pg_logical_slot_peek_changes('cdc_movies', NULL, NULL)
LIMIT 10;

-- (11) Cleanup. Always drop slots you don't intend to keep. The orphan_demo
--      slot is the exact thing that fills production disks.
SELECT pg_drop_replication_slot('orphan_demo');
SELECT pg_drop_replication_slot('cdc_movies');

-- (12) Final inventory. Only standby_1 should remain.
SELECT slot_name, slot_type, active, restart_lsn
FROM pg_replication_slots;
