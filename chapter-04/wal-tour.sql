-- Chapter 4 WAL tour.
-- Run top to bottom against a freshly seeded cinetrack database.
-- Each numbered section maps to a moment in the chapter prose.

-- (1) Where are we in the WAL right now?
--     pg_current_wal_lsn() returns the LSN of the next byte to be written.
--     pg_walfile_name() maps an LSN to the file name that contains it.
SELECT pg_current_wal_lsn()                      AS current_lsn,
       pg_walfile_name(pg_current_wal_lsn())     AS current_segment;

-- (2) Measure WAL volume produced by a batch of writes.
--     The pg_lsn type subtracts to a number of bytes.
SELECT pg_current_wal_lsn() AS lsn_before \gset

INSERT INTO reviews (user_id, movie_id, body)
SELECT ((g - 1) % 25) + 1,
       ((g * 7)  % 50) + 1,
       'WAL volume measurement insert ' || g
FROM generate_series(1, 1000) AS g;

SELECT pg_current_wal_lsn()                              AS lsn_after,
       pg_current_wal_lsn() - :'lsn_before'::pg_lsn      AS wal_bytes;
-- wal_bytes is the WAL produced by 1,000 inserts. Compare it to the heap
-- growth (40-50 bytes per row) to see the full-page-write tax in action.

-- (3) The cluster-wide WAL stats view (Postgres 14+).
--     PG 17 columns: wal_records, wal_fpi, wal_bytes, wal_buffers_full,
--     wal_write, wal_sync, wal_write_time, wal_sync_time, stats_reset.
SELECT * FROM pg_stat_wal;

-- (4) Map an LSN to a (segment, offset) pair.
--     Useful when you're about to run pg_waldump and need the exact file.
SELECT * FROM pg_walfile_name_offset(pg_current_wal_lsn());

-- (5) Force a checkpoint and look at the control file's view of it.
--     pg_control_checkpoint() is the on-disk record of where recovery would
--     start from after a crash right now.
CHECKPOINT;
SELECT checkpoint_lsn,
       redo_lsn,
       pg_walfile_name(redo_lsn) AS redo_wal_file,
       redo_tli AS timeline_id,
       full_page_writes
FROM pg_control_checkpoint();

-- (6) Latency: synchronous_commit = on (the default).
--     A thousand single-row commits inside a procedure block, each waiting
--     for fsync. Procedure blocks let us script COMMIT explicitly so the
--     timing numbers reflect a per-row commit pattern.
\timing on
DO $$
BEGIN
    FOR i IN 1..1000 LOOP
        INSERT INTO reviews (user_id, movie_id, body)
        VALUES (((i - 1) % 25) + 1,
                ((i * 11) % 50) + 1,
                'sync_commit_on row ' || i);
        COMMIT;
    END LOOP;
END $$;
\timing off

-- (7) Latency: synchronous_commit = off (per session).
--     Same workload, same shape, but commits return before fsync.
SET synchronous_commit = off;
\timing on
DO $$
BEGIN
    FOR i IN 1..1000 LOOP
        INSERT INTO reviews (user_id, movie_id, body)
        VALUES (((i - 1) % 25) + 1,
                ((i * 11) % 50) + 1,
                'sync_commit_off row ' || i);
        COMMIT;
    END LOOP;
END $$;
\timing off
RESET synchronous_commit;
-- The off run is typically several times faster on consumer SSDs.
-- On NVMe with power-loss protection, the gap shrinks.

-- (8) Replication-slot inventory.
--     Empty on a single-node sandbox. In production, this is the table you
--     watch every morning for slots whose consumers have walked off.
SELECT slot_name, slot_type, active, restart_lsn,
       pg_current_wal_lsn() - restart_lsn AS bytes_pinned
FROM pg_replication_slots;

-- (9) Watch a checkpoint cycle live.
--     With log_checkpoints = on (set in docker-compose.yml), every checkpoint
--     prints a summary line to the container log. Generate enough WAL to
--     trip max_wal_size = 128MB and observe the "checkpoint starting: wal"
--     line in `docker logs -f cinetrack-pg-ch04`.
INSERT INTO view_events (user_id, movie_id, duration_sec)
SELECT ((g - 1) % 25) + 1,
       ((g * 17) % 50) + 1,
       60 + (g % 1800)
FROM generate_series(1, 200000) AS g;

-- (10) WAL size on disk versus the configured cap.
--      pg_wal_lsn_diff against the pre-checkpoint LSN approximates how much
--      WAL is currently retained for recovery.
SELECT pg_size_pretty(pg_wal_lsn_diff(
           pg_current_wal_lsn(),
           (SELECT redo_lsn FROM pg_control_checkpoint())
       )) AS wal_since_last_checkpoint;
