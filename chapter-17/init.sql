-- Cinetrack chapter-17 schema.
-- Reuses the cinetrack core (movies, users, reviews, watchlists, follows)
-- and adds the queue and outbox tables that the chapter walks through.
--
-- Two patterns live here side by side:
--   - notifications: a job queue, claimed concurrently with SKIP LOCKED
--   - outbox:        a transactional event log, drained by a publisher
-- Both have partial indexes that keep claim queries fast as the underlying
-- tables grow.

BEGIN;

CREATE TABLE IF NOT EXISTS movies (
    id            BIGSERIAL PRIMARY KEY,
    title         TEXT        NOT NULL,
    release_year  INT         NOT NULL,
    runtime_min   INT,
    director      TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS users (
    id            BIGSERIAL PRIMARY KEY,
    username      TEXT        NOT NULL UNIQUE,
    email         TEXT        NOT NULL UNIQUE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS follows (
    follower_id   BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    followed_id   BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (follower_id, followed_id),
    CHECK (follower_id <> followed_id)
);

CREATE TABLE IF NOT EXISTS reviews (
    id            BIGSERIAL PRIMARY KEY,
    user_id       BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    movie_id      BIGINT      NOT NULL REFERENCES movies(id) ON DELETE CASCADE,
    body          TEXT        NOT NULL,
    posted_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- The notifications queue: a job table with claim-and-process semantics.
-- One row per (recipient, event). Workers claim batches and dispatch
-- to the push gateway.
CREATE TABLE IF NOT EXISTS notifications (
    id            BIGSERIAL PRIMARY KEY,
    recipient_id  BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    kind          TEXT        NOT NULL
                  CHECK (kind IN ('review_posted', 'follow', 'reply')),
    payload       JSONB       NOT NULL,
    status        TEXT        NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending', 'running', 'done', 'failed')),
    attempts      INT         NOT NULL DEFAULT 0,
    max_attempts  INT         NOT NULL DEFAULT 5,
    run_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    locked_by     TEXT,
    locked_at     TIMESTAMPTZ,
    last_error    TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- The partial index that powers the claim query.
-- Only pending rows are indexed; done/failed rows live outside it.
-- Order matches the claim's ORDER BY exactly so the planner uses an
-- in-order index walk and stops at the first unlocked row.
CREATE INDEX IF NOT EXISTS idx_notifications_pending
    ON notifications (run_at, id)
    WHERE status = 'pending';

-- The transactional outbox.
-- One row per business event the application wants to publish to Kafka.
-- The application writes business state and outbox rows in one transaction;
-- a separate publisher forwards published_at IS NULL rows.
CREATE TABLE IF NOT EXISTS outbox (
    id              BIGSERIAL PRIMARY KEY,
    aggregate_type  TEXT        NOT NULL,
    aggregate_id    TEXT        NOT NULL,
    event_type      TEXT        NOT NULL,
    payload         JSONB       NOT NULL,
    headers         JSONB       NOT NULL DEFAULT '{}'::jsonb,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    published_at    TIMESTAMPTZ
);

-- Partial index: only unpublished rows. The publisher's claim is fast
-- regardless of how big the table grows from accumulated published rows.
CREATE INDEX IF NOT EXISTS idx_outbox_unpublished
    ON outbox (id)
    WHERE published_at IS NULL;

-- Wakeup wiring. A trigger on notifications fires pg_notify on every
-- pending insert; the worker LISTENs on the channel and skips the
-- polling cost on a quiet queue.
CREATE OR REPLACE FUNCTION notify_notifications_pending()
RETURNS TRIGGER AS $$
BEGIN
    PERFORM pg_notify('notifications_pending', '');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_notifications_notify ON notifications;
CREATE TRIGGER trg_notifications_notify
AFTER INSERT ON notifications
FOR EACH ROW
WHEN (NEW.status = 'pending')
EXECUTE FUNCTION notify_notifications_pending();

CREATE OR REPLACE FUNCTION notify_outbox_pending()
RETURNS TRIGGER AS $$
BEGIN
    PERFORM pg_notify('outbox_pending', '');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_outbox_notify ON outbox;
CREATE TRIGGER trg_outbox_notify
AFTER INSERT ON outbox
FOR EACH ROW
WHEN (NEW.published_at IS NULL)
EXECUTE FUNCTION notify_outbox_pending();

-- Useful B-tree on reviews so the fanout query (followers of an author)
-- doesn't scan the whole reviews table.
CREATE INDEX IF NOT EXISTS idx_reviews_user_id ON reviews (user_id);
CREATE INDEX IF NOT EXISTS idx_follows_followed ON follows (followed_id);

COMMIT;
