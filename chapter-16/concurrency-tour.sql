-- Chapter 16 concurrency tour.
-- Run top to bottom against a freshly seeded cinetrack database, or open it
-- in psql and step through numbered blocks. Sections 4 and 11 want two psql
-- sessions to see the contention behavior; the file annotates which lines go
-- in session A and which in session B.

-- ---------------------------------------------------------------------------
-- (1) The SKIP LOCKED queue primitive.
--     Plain SELECT FOR UPDATE blocks. SKIP LOCKED moves on to the next row.
-- ---------------------------------------------------------------------------
SELECT id, status, payload->>'body' AS body
FROM jobs
WHERE status = 'pending'
ORDER BY created_at
LIMIT 1
FOR UPDATE SKIP LOCKED;
-- Run this in two psql sessions back-to-back inside transactions; each
-- session locks a different row. Without SKIP LOCKED, the second session
-- would block on the first.

-- ---------------------------------------------------------------------------
-- (2) The leased-work pattern.
--     One round trip: claim the next job AND record the lease in jobs itself.
-- ---------------------------------------------------------------------------
BEGIN;
UPDATE jobs
SET status     = 'running',
    locked_by  = 'worker-' || pg_backend_pid(),
    locked_at  = now(),
    attempts   = attempts + 1
WHERE id = (
    SELECT id FROM jobs
    WHERE status = 'pending'
    ORDER BY created_at
    LIMIT 1
    FOR UPDATE SKIP LOCKED
)
RETURNING id, payload, attempts;
COMMIT;

-- ---------------------------------------------------------------------------
-- (3) Advisory locks: session vs. transaction scope.
--     Transaction-scoped releases on COMMIT/ROLLBACK; session-scoped does not.
-- ---------------------------------------------------------------------------
BEGIN;
SELECT pg_advisory_xact_lock(hashtext('cinetrack:demo:rollup'));
-- Do work that needs single-leader semantics here.
COMMIT;
-- Lock released. No pg_advisory_unlock() needed.

-- The work-or-skip variant: don't wait, don't queue.
SELECT pg_try_advisory_xact_lock(hashtext('cinetrack:demo:rollup')) AS got_lock;

-- ---------------------------------------------------------------------------
-- (4) Cross-session advisory lock visibility.
--     In session A:   SELECT pg_advisory_lock(42);  (leave it; do not release)
--     In session B:   run the next two lines.
-- ---------------------------------------------------------------------------
SELECT pid, locktype, classid, objid, mode, granted
FROM pg_locks
WHERE locktype = 'advisory';
-- objid is the lower 32 bits of the lock key. Match it back to the code that
-- holds it. This is the debugging tool when an advisory lock has gone rogue.

-- WARNING: don't forget to release the lock in session A. Run
--    SELECT pg_advisory_unlock(42);
-- at the end of session A, or close the session entirely. Session-scoped
-- advisory locks survive transaction COMMIT/ROLLBACK and only release on
-- explicit unlock or session disconnect. A forgotten lock here is exactly the
-- "advisory lock has gone rogue" case the query above was written to debug.

-- ---------------------------------------------------------------------------
-- (5) Optimistic concurrency on a review.
--     Add a version column at write time. Increment it. Refuse writes that
--     don't carry the right previous value.
-- ---------------------------------------------------------------------------
SELECT id, body, version FROM reviews WHERE id = 1;
-- Note the version. Pretend you are a worker that's about to compute a new body.

UPDATE reviews
SET body    = body || ' (edited)',
    version = version + 1,
    edited_at = now()
WHERE id = 1
  AND version = 1
RETURNING id, version;
-- One row returned: you won. Now retry the same UPDATE with version = 1 again:

UPDATE reviews
SET body    = body || ' (edited)',
    version = version + 1
WHERE id = 1
  AND version = 1
RETURNING id, version;
-- Zero rows returned: somebody else (you, on the previous statement) updated
-- the row. The retry-loop in your application sees the empty RETURNING and
-- re-reads.
-- NOTE: this second UPDATE only returns zero rows on a database where the
-- first UPDATE already ran. If you re-run the seed (or run this section
-- against a fresh seed) the version column resets to 1 and the second
-- UPDATE will *succeed*, because the seed has not yet been bumped to 2.
-- Run the two UPDATEs back to back in the same psql session to see the
-- intended "second one fails" behavior.

-- ---------------------------------------------------------------------------
-- (6) Idempotency-key claim.
--     INSERT ... ON CONFLICT DO NOTHING with RETURNING tells you whether you
--     are the first writer for this key.
-- ---------------------------------------------------------------------------
INSERT INTO idempotency_keys (key, request_hash)
VALUES ('demo-key-001', md5('{"score":8,"movie":1}'))
ON CONFLICT (key) DO NOTHING
RETURNING key;
-- One row returned: you claimed it. Do the work, then UPDATE the row with the
-- response and status code.

INSERT INTO idempotency_keys (key, request_hash)
VALUES ('demo-key-001', md5('{"score":8,"movie":1}'))
ON CONFLICT (key) DO NOTHING
RETURNING key;
-- Empty: somebody (you, on the previous run) already has it. Read the cached
-- response.

SELECT key, request_hash, response, status_code FROM idempotency_keys
WHERE key = 'demo-key-001';

-- ---------------------------------------------------------------------------
-- (7) The cinetrack rating upsert.
--     ON CONFLICT DO UPDATE on (user_id, movie_id). EXCLUDED is the new row.
--     RETURNING (xmax = 0) tells you whether this was an insert or an update.
-- ---------------------------------------------------------------------------
INSERT INTO ratings (user_id, movie_id, score, rated_at)
VALUES (1, 1, 9, now())
ON CONFLICT (user_id, movie_id) DO UPDATE
    SET score    = EXCLUDED.score,
        rated_at = now()
RETURNING id, score, (xmax = 0) AS was_insert;
-- Re-run with score = 7: was_insert is false, score is updated.

-- ---------------------------------------------------------------------------
-- (8) The classic EXCLUDED gotcha.
--     `SET score = score` is a no-op. `SET score = EXCLUDED.score` writes the
--     new value. Both parse fine.
-- ---------------------------------------------------------------------------
INSERT INTO ratings (user_id, movie_id, score) VALUES (1, 2, 4)
ON CONFLICT (user_id, movie_id) DO UPDATE
    SET score = ratings.score                    -- WRONG: keeps the old value
RETURNING score;

INSERT INTO ratings (user_id, movie_id, score) VALUES (1, 2, 6)
ON CONFLICT (user_id, movie_id) DO UPDATE
    SET score = EXCLUDED.score                   -- RIGHT: writes the new value
RETURNING score;

-- ---------------------------------------------------------------------------
-- (9) The full rating endpoint: upsert + incremental aggregate.
--     One transaction. Two statements. The aggregate update sidesteps the
--     hot-row optimistic-concurrency problem.
-- ---------------------------------------------------------------------------
-- The pre-image read has to happen in its own CTE because RETURNING from an
-- INSERT ... ON CONFLICT DO UPDATE evaluates columns AFTER the action runs:
-- on the update path, ratings.score already equals EXCLUDED.score, so you
-- cannot read the previous value out of RETURNING. The FOR UPDATE on the
-- pre-image keeps a concurrent updater from changing the score between our
-- read and our write.
BEGIN;

WITH existing AS (
    SELECT score AS prev_score
    FROM ratings
    WHERE user_id = 2 AND movie_id = 1
    FOR UPDATE
),
upsert AS (
    INSERT INTO ratings (user_id, movie_id, score, rated_at)
    VALUES (2, 1, 10, now())
    ON CONFLICT (user_id, movie_id) DO UPDATE
        SET score    = EXCLUDED.score,
            rated_at = now()
    RETURNING (xmax = 0) AS was_insert,
              score      AS new_score
)
UPDATE movies
SET (rating_count, rating_sum) = (
        rating_count + CASE WHEN u.was_insert THEN 1 ELSE 0 END,
        rating_sum   + u.new_score - COALESCE(e.prev_score, 0)
    )
FROM upsert u LEFT JOIN existing e ON true
WHERE id = 1
RETURNING id, rating_count, rating_sum,
          rating_sum::numeric / NULLIF(rating_count, 0) AS avg_score;

COMMIT;

-- ---------------------------------------------------------------------------
-- (10) MERGE on Postgres 17.
--      Useful when you have multiple cases beyond "row exists / row doesn't."
-- ---------------------------------------------------------------------------
MERGE INTO ratings AS r
USING (VALUES (3, 1, 8)) AS new_data(user_id, movie_id, score)
ON r.user_id = new_data.user_id AND r.movie_id = new_data.movie_id
WHEN MATCHED AND r.score = new_data.score THEN
    DO NOTHING
WHEN MATCHED THEN
    UPDATE SET score = new_data.score, rated_at = now()
WHEN NOT MATCHED THEN
    INSERT (user_id, movie_id, score) VALUES (new_data.user_id, new_data.movie_id, new_data.score);

-- ---------------------------------------------------------------------------
-- (11) Watching the queue under contention. (Two-session demo.)
--      Open four psql sessions. Each runs:
--
--        BEGIN;
--        SELECT id FROM jobs WHERE status='pending'
--        ORDER BY created_at LIMIT 1
--        FOR UPDATE SKIP LOCKED;
--
--      Then in a fifth session, watch:
SELECT pid, state, wait_event_type, wait_event,
       query_start, substring(query, 1, 60) AS q
FROM pg_stat_activity
WHERE state IS NOT NULL AND backend_type = 'client backend'
ORDER BY query_start NULLS LAST;
-- None of the four sessions are waiting. Each has its own job locked. That's
-- the conveyor belt: no worker waits for another worker, and the queue drains
-- as fast as the workers can process.

-- ---------------------------------------------------------------------------
-- (12) Cleanup peek.
--      Idempotency keys grow forever without a TTL. A daily prune is enough
--      for almost any workload.
-- ---------------------------------------------------------------------------
SELECT count(*) FROM idempotency_keys
WHERE created_at < now() - interval '24 hours';

-- The actual prune:
-- DELETE FROM idempotency_keys WHERE created_at < now() - interval '24 hours';
