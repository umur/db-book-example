-- Chapter 17 queue and outbox tour.
-- Run top to bottom against a freshly seeded cinetrack database.
-- Each numbered section maps to a moment in the chapter prose.
-- Sections (5) and (6) are best run from two separate psql sessions to
-- watch SKIP LOCKED in action; instructions are inline.

-- (1) The fanout-in-one-transaction pattern.
--     A user posts a review. Three writes (review + outbox event +
--     per-follower notifications) commit together or roll back together.
--     This is the application-side write the chapter's 17.7 walks through.
BEGIN;

WITH new_review AS (
    INSERT INTO reviews (user_id, movie_id, body)
    VALUES (1, 42, 'A slow burn that rewards patient viewers.')
    RETURNING id, user_id, movie_id, body
),
event AS (
    INSERT INTO outbox (aggregate_type, aggregate_id, event_type, payload)
    SELECT 'Review', r.id::text, 'ReviewPosted',
           jsonb_build_object(
               'reviewId', r.id,
               'authorId', r.user_id,
               'movieId',  r.movie_id,
               'body',     r.body
           )
    FROM new_review r
    RETURNING id
)
INSERT INTO notifications (recipient_id, kind, payload)
SELECT f.follower_id, 'review_posted',
       jsonb_build_object(
           'reviewId', r.id,
           'authorId', r.user_id,
           'movieId',  r.movie_id
       )
FROM new_review r
JOIN follows f ON f.followed_id = r.user_id;

COMMIT;

-- Confirm the three sides of the write all landed.
SELECT 'reviews'       AS tbl, count(*) FROM reviews       WHERE user_id = 1 AND movie_id = 42
UNION ALL SELECT 'outbox',         count(*) FROM outbox        WHERE aggregate_type = 'Review' AND published_at IS NULL
UNION ALL SELECT 'notifications',  count(*) FROM notifications WHERE status = 'pending';

-- (2) The partial index that makes claims fast.
--     idx_notifications_pending only covers status='pending' rows.
--     As done/failed rows accumulate, the index size stays bounded
--     to the current pending backlog.
SELECT relname, indexrelname,
       pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE indexrelname IN ('idx_notifications_pending', 'idx_outbox_unpublished');

-- (3) The claim plan with the partial index.
--     Expect: Index Scan on idx_notifications_pending, LIMIT, then the
--     row-level lock acquired via SKIP LOCKED. Fast and bounded.
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, recipient_id, kind, payload
FROM notifications
WHERE status = 'pending'
  AND run_at <= now()
ORDER BY run_at, id
LIMIT 10
FOR UPDATE SKIP LOCKED;

-- (4) The single-statement claim. One worker, batch of 25.
--     Returns the claimed rows; the application processes each one
--     and then UPDATEs status to 'done' or back to 'pending' on failure.
UPDATE notifications
SET status     = 'running',
    locked_by  = 'worker-demo-A',
    locked_at  = now(),
    attempts   = attempts + 1,
    updated_at = now()
WHERE id IN (
    SELECT id
    FROM notifications
    WHERE status = 'pending'
      AND run_at <= now()
    ORDER BY run_at, id
    LIMIT 25
    FOR UPDATE SKIP LOCKED
)
RETURNING id, recipient_id, kind, attempts;

-- (5) Multi-worker simulation.
--     To see SKIP LOCKED skip rows held by another transaction, open a
--     SECOND psql session and run:
--
--         BEGIN;
--         SELECT id FROM notifications
--         WHERE status = 'pending' AND run_at <= now()
--         ORDER BY run_at, id LIMIT 5
--         FOR UPDATE SKIP LOCKED;
--         -- (leave the transaction open)
--
--     Then come back to THIS session and run the claim below. Note that
--     the second session's row IDs do not appear in the result. SKIP
--     LOCKED walks past them.
UPDATE notifications
SET status     = 'running',
    locked_by  = 'worker-demo-B',
    locked_at  = now(),
    attempts   = attempts + 1,
    updated_at = now()
WHERE id IN (
    SELECT id
    FROM notifications
    WHERE status = 'pending'
      AND run_at <= now()
    ORDER BY run_at, id
    LIMIT 10
    FOR UPDATE SKIP LOCKED
)
RETURNING id, locked_by;
-- After observing the result, COMMIT or ROLLBACK in the second session
-- to release the locks before continuing.

-- (6) Completing claimed jobs.
--     The worker writes results, then flips status to 'done'.
UPDATE notifications
SET status     = 'done',
    updated_at = now()
WHERE locked_by IN ('worker-demo-A', 'worker-demo-B')
  AND status   = 'running';

-- (7) Failure with exponential backoff.
--     Pick a still-pending row and pretend the dispatch failed. The
--     CASE expression either re-pends with backoff or sends to the
--     dead-letter state if max_attempts is exceeded.
UPDATE notifications
SET status     = CASE
                     WHEN attempts >= max_attempts THEN 'failed'
                     ELSE 'pending'
                 END,
    run_at     = CASE
                     WHEN attempts >= max_attempts THEN run_at
                     ELSE now() + (interval '1 minute' * power(2, attempts))
                 END,
    last_error = 'simulated push gateway failure',
    updated_at = now()
WHERE id = (SELECT id FROM notifications WHERE status = 'pending' LIMIT 1)
RETURNING id, status, attempts, run_at, last_error;

-- (8) Outbox publisher claim.
--     Same SKIP LOCKED pattern, different table, different semantics.
--     The publisher reads, forwards each row to Kafka in application code,
--     then marks the rows published. SKIP LOCKED lets two publishers run
--     concurrently without ever publishing the same row twice.
--
--     The tour version below is a single-publisher demo: it captures the
--     claimed ids in a temp table within a BEGIN/COMMIT block so the locks
--     are held across the (simulated) Kafka publish. Production publishers
--     must keep the transaction open across both the publish call and the
--     UPDATE; otherwise SKIP LOCKED gives no protection between claims.
BEGIN;

CREATE TEMP TABLE claimed_outbox ON COMMIT DROP AS
SELECT id, aggregate_type, aggregate_id, event_type, payload
FROM outbox
WHERE published_at IS NULL
ORDER BY id
LIMIT 100
FOR UPDATE SKIP LOCKED;

SELECT * FROM claimed_outbox;
-- (in the application: publish each row in claimed_outbox to Kafka here,
-- still inside this transaction so the row locks are held)

UPDATE outbox
SET published_at = now()
WHERE id = ANY (SELECT id FROM claimed_outbox);

COMMIT;

-- (9) LISTEN / NOTIFY wakeup demo.
--     Run the LISTEN below. Then in a SECOND psql session, INSERT a new
--     review using the section (1) pattern. The triggers fire pg_notify
--     on commit, and this session prints the notifications immediately.
LISTEN notifications_pending;
LISTEN outbox_pending;

-- After running the LISTEN above, this session is now subscribed.
-- In a SECOND session, run:
--   BEGIN;
--   INSERT INTO outbox (aggregate_type, aggregate_id, event_type, payload)
--   VALUES ('Review', '999', 'ReviewPosted', '{"demo": true}'::jsonb);
--   COMMIT;
-- This session will receive an outbox_pending notification on commit.
-- (psql shows notifications between commands; press Enter to flush.)

-- (10) Dead-letter handling.
--     Inspect failed rows, group by kind for triage, and (optionally)
--     re-pend after a fix.
SELECT id, kind, attempts, last_error, updated_at
FROM notifications
WHERE status = 'failed'
ORDER BY updated_at DESC
LIMIT 25;

-- Re-pend a specific failed row after fixing the underlying issue.
-- Replace 999 with a real id from the query above.
-- UPDATE notifications
-- SET status = 'pending', attempts = 0, last_error = NULL,
--     run_at = now(), updated_at = now()
-- WHERE id = 999;

-- (11) Sweeper for stuck running rows.
--     A worker that died holding a 'running' row leaves the row stuck.
--     A periodic job re-pends rows whose locked_at is older than the
--     reasonable processing time.
UPDATE notifications
SET status     = 'pending',
    locked_by  = NULL,
    locked_at  = NULL,
    updated_at = now()
WHERE status     = 'running'
  AND locked_at  < now() - interval '5 minutes'
RETURNING id, attempts, locked_at;

-- (12) Outbox cleanup.
--     Published rows older than 7 days are safe to delete; Kafka is the
--     durable record after the publish. The partial index stays small
--     because it was already excluding these rows.
DELETE FROM outbox
WHERE published_at < now() - interval '7 days';

-- Sanity check at the end of the tour.
SELECT 'pending notifications' AS metric, count(*) FROM notifications WHERE status = 'pending'
UNION ALL SELECT 'running notifications',     count(*) FROM notifications WHERE status = 'running'
UNION ALL SELECT 'done notifications',        count(*) FROM notifications WHERE status = 'done'
UNION ALL SELECT 'failed notifications',      count(*) FROM notifications WHERE status = 'failed'
UNION ALL SELECT 'unpublished outbox',        count(*) FROM outbox        WHERE published_at IS NULL
UNION ALL SELECT 'published outbox',          count(*) FROM outbox        WHERE published_at IS NOT NULL;
