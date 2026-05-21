-- Chapter 2 MVCC tour.
-- Run top to bottom against a freshly seeded cinetrack database.
-- Each numbered section maps to a moment in the chapter prose.

-- (1) The system columns Postgres exposes on every row.
--     xmin = inserting transaction id
--     xmax = deleting/updating transaction id (0 if alive)
--     ctid = physical (page, offset) of this tuple version on disk
SELECT xmin, xmax, ctid, id, substring(body, 1, 30) AS body
FROM reviews
ORDER BY id
LIMIT 5;

-- (2) Peek at the current transaction id and snapshot.
--     A SELECT-only transaction does not consume an xid; calling
--     pg_current_xact_id() forces one to be assigned.
--     pg_current_xact_id() is the modern (xid8, wrap-safe) form;
--     txid_current() is the deprecated alias kept for back-compat.
SELECT pg_current_xact_id()     AS current_xid,
       pg_current_snapshot()    AS current_snapshot;

-- (3) Watch an UPDATE move the ctid and shift xmin.
SELECT xmin, xmax, ctid, id FROM reviews WHERE id = 1;
UPDATE reviews SET body = body || ' (edited)', edited_at = now() WHERE id = 1;
SELECT xmin, xmax, ctid, id FROM reviews WHERE id = 1;
-- New ctid (the row landed at a new physical position).
-- New xmin (the update transaction's xid).
-- The old tuple is still on disk, dead, with xmax set to the update xid.

-- (4) Live vs. dead tuple counts before we churn.
-- pg_stat_clear_snapshot() forces this session to refetch cumulative stats.
-- Without it, the per-session snapshot can be a few seconds stale.
ANALYZE reviews;
SELECT pg_stat_force_next_flush();
SELECT pg_stat_clear_snapshot();
SELECT relname, n_live_tup, n_dead_tup, n_tup_upd, n_tup_hot_upd
FROM pg_stat_user_tables
WHERE relname = 'reviews';

-- (5) Make dead tuples climb. 1,000 updates on a single review.
DO $$
BEGIN
    FOR i IN 1..1000 LOOP
        UPDATE reviews SET body = body || '' WHERE id = 2;
    END LOOP;
END $$;

ANALYZE reviews;
SELECT pg_stat_force_next_flush();
SELECT pg_stat_clear_snapshot();
SELECT relname, n_live_tup, n_dead_tup, n_tup_upd, n_tup_hot_upd,
       pg_size_pretty(pg_relation_size('reviews')) AS heap_size
FROM pg_stat_user_tables
WHERE relname = 'reviews';
-- n_dead_tup should be near 1,000.
-- n_tup_hot_upd should be high: body is not indexed, so most of these are HOT.

-- (6) Reclaim dead space.
VACUUM (VERBOSE, ANALYZE) reviews;

SELECT pg_stat_force_next_flush();
SELECT pg_stat_clear_snapshot();
SELECT relname, n_live_tup, n_dead_tup,
       pg_size_pretty(pg_relation_size('reviews')) AS heap_size
FROM pg_stat_user_tables
WHERE relname = 'reviews';
-- n_dead_tup back near zero. Heap size unchanged: vacuum reclaims space
-- inside the heap, not back to the OS. VACUUM FULL or pg_repack does the latter.

-- (7) HOT vs. non-HOT.
--     Body is unindexed -> updates are HOT.
--     movie_id is indexed (idx_reviews_movie_id) -> updates are non-HOT.
SELECT pg_stat_force_next_flush();
SELECT pg_stat_clear_snapshot();
SELECT n_tup_upd, n_tup_hot_upd FROM pg_stat_user_tables WHERE relname = 'reviews';

UPDATE reviews SET body = body || '.' WHERE id = 3;            -- HOT eligible
UPDATE reviews SET movie_id = movie_id + 1 WHERE id = 3;       -- non-HOT (indexed col actually changes)
UPDATE reviews SET movie_id = movie_id - 1 WHERE id = 3;       -- restore the original value

ANALYZE reviews;
SELECT pg_stat_force_next_flush();
SELECT pg_stat_clear_snapshot();
SELECT n_tup_upd, n_tup_hot_upd FROM pg_stat_user_tables WHERE relname = 'reviews';

-- (8) DELETE is a tombstone.
--     Watch the heap size NOT shrink on delete.
SELECT pg_size_pretty(pg_relation_size('reviews')) AS heap_before_delete;

DELETE FROM reviews WHERE id IN (40, 41, 42, 43, 44);

SELECT pg_size_pretty(pg_relation_size('reviews')) AS heap_after_delete;
-- Same size. The tombstones just mark the rows dead.

VACUUM reviews;
SELECT pg_size_pretty(pg_relation_size('reviews')) AS heap_after_vacuum;
-- Still the same size on disk. Vacuum reclaims internal space.

-- (9) The long-transaction trap.
--     In session A:   BEGIN ISOLATION LEVEL REPEATABLE READ;
--                     SELECT id FROM reviews WHERE id = 1;
--                     (leave it open; do not COMMIT yet)
--     Read Committed will not pin xmin here: backend_xmin advances after the
--     statement finishes. REPEATABLE READ pins the snapshot for the whole
--     transaction, which is what we need to demo.
--     In session B:   run this block and watch n_dead_tup refuse to go to zero.
DO $$
BEGIN
    FOR i IN 1..500 LOOP
        UPDATE reviews SET body = body || '' WHERE id = 4;
    END LOOP;
END $$;

VACUUM reviews;
SELECT pg_stat_force_next_flush();
SELECT pg_stat_clear_snapshot();
SELECT n_dead_tup FROM pg_stat_user_tables WHERE relname = 'reviews';
-- If session A is still in transaction, n_dead_tup will be much higher than 0.
-- After session A's COMMIT, run the next two lines:
VACUUM reviews;
SELECT pg_stat_force_next_flush();
SELECT pg_stat_clear_snapshot();
SELECT n_dead_tup FROM pg_stat_user_tables WHERE relname = 'reviews';

-- (10) Visibility-horizon view.
--     pg_stat_activity tells you the oldest in-flight transaction.
SELECT pid,
       state,
       backend_xmin,
       xact_start,
       now() - xact_start AS xact_age,
       query_start
FROM pg_stat_activity
WHERE backend_type = 'client backend'
  AND state IS NOT NULL
ORDER BY xact_start NULLS LAST;
-- backend_xmin is the snapshot horizon held by that session.
-- The oldest one across the whole server is what vacuum can advance up to.

-- (11) Per-tuple system columns of a DELETED row are no longer visible
--      to a normal SELECT. The row exists physically, but the visibility
--      check filters it out.
SELECT count(*) AS visible_rows FROM reviews;

-- (12) Bloat snapshot for the whole database, sorted by waste.
SELECT pg_stat_force_next_flush();
SELECT pg_stat_clear_snapshot();
SELECT s.relname,
       s.n_live_tup,
       s.n_dead_tup,
       round(100.0 * s.n_dead_tup / NULLIF(s.n_live_tup + s.n_dead_tup, 0), 1) AS dead_pct,
       pg_size_pretty(pg_relation_size(c.oid))      AS heap,
       pg_size_pretty(pg_indexes_size(c.oid))       AS indexes
FROM pg_stat_user_tables s
JOIN pg_class c ON c.oid = s.relid
ORDER BY s.n_dead_tup DESC NULLS LAST;
