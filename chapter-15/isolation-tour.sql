-- Chapter 15 isolation and locking tour.
--
-- Most of these demos require TWO psql sessions running side by side. The
-- comments below mark each session. Run a section in one window, switch to
-- the other, and so on.
--
-- Echo input/output so the comparisons are visible in the terminal log.
\set ECHO all

-- ---------------------------------------------------------------------------
-- (1) Read Committed: statement-level snapshots.
--
-- Session A:  BEGIN;
--             SELECT score FROM ratings WHERE id = 1;   -- note the value
-- Session B:  UPDATE ratings SET score = score + 1 WHERE id = 1;
-- Session A:  SELECT score FROM ratings WHERE id = 1;   -- one higher
--             COMMIT;
--
-- The two SELECTs in session A return different values because each
-- statement takes a fresh snapshot. This is the defining behavior of
-- Read Committed.

-- ---------------------------------------------------------------------------
-- (2) Read Committed: lost update without FOR UPDATE.
--
-- Session A:  BEGIN;
--             SELECT quota FROM movies WHERE id = 1;          -- 10
-- Session B:  BEGIN;
--             SELECT quota FROM movies WHERE id = 1;          -- 10
-- Session A:  UPDATE movies SET quota = 9 WHERE id = 1;
--             COMMIT;
-- Session B:  UPDATE movies SET quota = 9 WHERE id = 1;       -- blocks
--                                                              -- then runs
--             COMMIT;
--
-- Both sessions read 10. Both wrote 9. The quota went from 10 to 9, not 8.
-- No error. This is the lost update.

-- ---------------------------------------------------------------------------
-- (3) Read Committed: fixed with SELECT ... FOR UPDATE.
--
-- Session A:  BEGIN;
--             SELECT quota FROM movies WHERE id = 2 FOR UPDATE;  -- locks
--             UPDATE movies SET quota = quota - 1 WHERE id = 2;
--             COMMIT;
-- Session B:  BEGIN;
--             SELECT quota FROM movies WHERE id = 2 FOR UPDATE;  -- waits
-- (after A commits)
--             UPDATE movies SET quota = quota - 1 WHERE id = 2;
--             COMMIT;
--
-- Session B re-reads the locked row after A commits and works on the
-- current value. Quota goes 10 -> 9 -> 8. Correct.

-- ---------------------------------------------------------------------------
-- (4) Repeatable Read: phantom read prevention.
--
-- Session A:  BEGIN ISOLATION LEVEL REPEATABLE READ;
--             SELECT count(*) FROM ratings WHERE movie_id = 3;  -- e.g. 6
-- Session B:  INSERT INTO ratings (user_id, movie_id, score)
--             VALUES (1, 3, 9) ON CONFLICT DO NOTHING;
-- Session A:  SELECT count(*) FROM ratings WHERE movie_id = 3;  -- still 6
--             COMMIT;
--             SELECT count(*) FROM ratings WHERE movie_id = 3;  -- now 7
--
-- Two reads inside the transaction agree. The third read, after COMMIT,
-- sees the new world.

-- ---------------------------------------------------------------------------
-- (5) Repeatable Read: lost update becomes a serialization failure.
--
-- Session A:  BEGIN ISOLATION LEVEL REPEATABLE READ;
--             SELECT quota FROM movies WHERE id = 4;     -- 10
-- Session B:  BEGIN ISOLATION LEVEL REPEATABLE READ;
--             SELECT quota FROM movies WHERE id = 4;     -- 10
-- Session A:  UPDATE movies SET quota = 9 WHERE id = 4;
--             COMMIT;
-- Session B:  UPDATE movies SET quota = 9 WHERE id = 4;  -- blocks, then:
--             ERROR:  could not serialize access due to concurrent update
--             ROLLBACK;
--
-- Session B's snapshot is too old to update the now-changed row. The
-- application is expected to catch SQLSTATE 40001 and retry.

-- ---------------------------------------------------------------------------
-- (6) Repeatable Read: write skew that survives.
--
-- The "at most one featured rating per movie" invariant. Repeatable Read
-- does not catch this; only Serializable does.
--
-- Session A:  BEGIN ISOLATION LEVEL REPEATABLE READ;
--             SELECT count(*) FROM ratings WHERE movie_id = 5 AND featured;
--             -- 0
-- Session B:  BEGIN ISOLATION LEVEL REPEATABLE READ;
--             SELECT count(*) FROM ratings WHERE movie_id = 5 AND featured;
--             -- 0
-- Session A:  UPDATE ratings SET featured = true
--             WHERE id = (SELECT id FROM ratings WHERE movie_id = 5
--                         ORDER BY id LIMIT 1);
-- Session B:  UPDATE ratings SET featured = true
--             WHERE id = (SELECT id FROM ratings WHERE movie_id = 5
--                         ORDER BY id OFFSET 1 LIMIT 1);
-- Session A:  COMMIT;
-- Session B:  COMMIT;
--
-- Both committed. Now run:
SELECT count(*) FROM ratings WHERE movie_id = 5 AND featured;
-- -- 2.  Invariant violated. This is write skew.

-- Reset for the next demo:
UPDATE ratings SET featured = false WHERE movie_id = 5;

-- ---------------------------------------------------------------------------
-- (7) Serializable: write skew is detected.
--
-- Same scenario as (6) but at SERIALIZABLE.
--
-- Session A:  BEGIN ISOLATION LEVEL SERIALIZABLE;
--             SELECT count(*) FROM ratings WHERE movie_id = 6 AND featured;
-- Session B:  BEGIN ISOLATION LEVEL SERIALIZABLE;
--             SELECT count(*) FROM ratings WHERE movie_id = 6 AND featured;
-- Session A:  UPDATE ratings SET featured = true
--             WHERE id = (SELECT id FROM ratings WHERE movie_id = 6
--                         ORDER BY id LIMIT 1);
-- Session B:  UPDATE ratings SET featured = true
--             WHERE id = (SELECT id FROM ratings WHERE movie_id = 6
--                         ORDER BY id OFFSET 1 LIMIT 1);
-- Session A:  COMMIT;            -- succeeds
-- Session B:  COMMIT;            -- ERROR: could not serialize access due to
--                                --        read/write dependencies
--             ROLLBACK;
--
-- SSI's predicate locks caught the read-write dependency cycle and aborted
-- the second committer. Application retries on a fresh snapshot, where the
-- count now reads 1 and the second update is skipped.

-- ---------------------------------------------------------------------------
-- (8) Row-level locks: NOWAIT.
--
-- Session A:  BEGIN;
--             SELECT * FROM ratings WHERE id = 7 FOR UPDATE;
-- Session B:  SELECT * FROM ratings WHERE id = 7 FOR UPDATE NOWAIT;
--             ERROR:  could not obtain lock on row in relation "ratings"
--
-- NOWAIT is the right choice when "the row is busy" should fail fast.

-- ---------------------------------------------------------------------------
-- (9) Row-level locks: SKIP LOCKED (the queue pattern).
--
-- Session A:  BEGIN;
--             SELECT id FROM ratings
--             WHERE movie_id = 8
--             ORDER BY id
--             FOR UPDATE SKIP LOCKED
--             LIMIT 1;
--             -- locks one row, doesn't commit
-- Session B:  SELECT id FROM ratings
--             WHERE movie_id = 8
--             ORDER BY id
--             FOR UPDATE SKIP LOCKED
--             LIMIT 1;
--             -- returns the NEXT row; doesn't block
--
-- This is how a multi-worker queue runs: every worker takes a different
-- batch, no worker waits, no row is processed twice.

-- ---------------------------------------------------------------------------
-- (10) Deadlock from inconsistent acquisition order.
--
-- Session A:  BEGIN;
--             UPDATE ratings SET score = score WHERE id = 10;
-- Session B:  BEGIN;
--             UPDATE ratings SET score = score WHERE id = 11;
-- Session A:  UPDATE ratings SET score = score WHERE id = 11;   -- waits
-- Session B:  UPDATE ratings SET score = score WHERE id = 10;   -- waits
-- After deadlock_timeout (1s):
--   ERROR:  deadlock detected
--
-- One session is killed. The other proceeds.

-- ---------------------------------------------------------------------------
-- (11) Deadlock prevention: ORDER BY ... FOR UPDATE in a CTE.
--
-- Session A and Session B both run this:
--   BEGIN;
--   WITH locked AS (
--       SELECT id FROM ratings
--       WHERE movie_id = 12
--       ORDER BY id
--       FOR UPDATE
--   )
--   UPDATE ratings SET score = score
--   FROM locked
--   WHERE ratings.id = locked.id;
--   COMMIT;
--
-- Both acquire locks in ascending id order. Whichever starts first holds
-- the prefix; the other waits cleanly. No deadlock ever fires.

-- ---------------------------------------------------------------------------
-- (12) lock_timeout in action.
--
-- Session A:  BEGIN;
--             SELECT * FROM ratings WHERE id = 20 FOR UPDATE;
-- Session B:  SET lock_timeout = '500ms';
--             SELECT * FROM ratings WHERE id = 20 FOR UPDATE;
--             -- after 500ms:
--             ERROR:  canceling statement due to lock timeout
--
-- The application catches SQLSTATE 55P03 and retries on its own schedule.
-- Without lock_timeout, B would have waited until A committed.

-- ---------------------------------------------------------------------------
-- Diagnostic: who is waiting on whom right now?
SELECT
    blocked.pid           AS blocked_pid,
    blocked.query         AS blocked_query,
    blocking.pid          AS blocking_pid,
    blocking.query        AS blocking_query,
    blocked.wait_event,
    now() - blocked.query_start AS waited_for
FROM pg_stat_activity blocked
JOIN pg_stat_activity blocking
  ON blocking.pid = ANY(pg_blocking_pids(blocked.pid))
WHERE blocked.wait_event_type = 'Lock';
