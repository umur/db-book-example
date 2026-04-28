-- Cinetrack chapter-16 schema.
-- Same shape as earlier chapters, plus the columns and tables this chapter's
-- patterns need: a version column on reviews, aggregate columns on movies,
-- a jobs table for the SKIP LOCKED queue demo, and an idempotency_keys table.

BEGIN;

CREATE TABLE IF NOT EXISTS movies (
    id            BIGSERIAL PRIMARY KEY,
    title         TEXT        NOT NULL,
    release_year  INT         NOT NULL,
    runtime_min   INT,
    director      TEXT,
    rating_count  INT         NOT NULL DEFAULT 0,
    rating_sum    INT         NOT NULL DEFAULT 0,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS users (
    id            BIGSERIAL PRIMARY KEY,
    username      TEXT        NOT NULL UNIQUE,
    email         TEXT        NOT NULL UNIQUE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS ratings (
    id            BIGSERIAL PRIMARY KEY,
    user_id       BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    movie_id      BIGINT      NOT NULL REFERENCES movies(id) ON DELETE CASCADE,
    score         SMALLINT    NOT NULL CHECK (score BETWEEN 1 AND 10),
    rated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, movie_id)
);

CREATE TABLE IF NOT EXISTS reviews (
    id            BIGSERIAL PRIMARY KEY,
    user_id       BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    movie_id      BIGINT      NOT NULL REFERENCES movies(id) ON DELETE CASCADE,
    body          TEXT        NOT NULL,
    version       INT         NOT NULL DEFAULT 1,
    posted_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    edited_at     TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS notifications (
    id            BIGSERIAL PRIMARY KEY,
    user_id       BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    payload       JSONB       NOT NULL,
    delivered_at  TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- The SKIP LOCKED queue from section 16.2.
-- Status is one of pending, running, done, failed. We keep failed rows around
-- so the dead-letter pattern in chapter 17 has something to look at.
CREATE TABLE IF NOT EXISTS jobs (
    id            BIGSERIAL PRIMARY KEY,
    payload       JSONB       NOT NULL,
    status        TEXT        NOT NULL DEFAULT 'pending'
                              CHECK (status IN ('pending','running','done','failed')),
    locked_by     TEXT,
    locked_at     TIMESTAMPTZ,
    attempts      INT         NOT NULL DEFAULT 0,
    last_error    TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_jobs_pending
    ON jobs (created_at) WHERE status = 'pending';

-- The idempotency table from section 16.5. Primary key is the client-supplied
-- key. request_hash lets us detect a client reusing the same key for a
-- different request body and respond with 422.
CREATE TABLE IF NOT EXISTS idempotency_keys (
    key           TEXT        PRIMARY KEY,
    request_hash  TEXT        NOT NULL,
    response      JSONB,
    status_code   INT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_movies_release_year ON movies (release_year);
CREATE INDEX IF NOT EXISTS idx_ratings_movie_id    ON ratings (movie_id);
CREATE INDEX IF NOT EXISTS idx_reviews_movie_id    ON reviews (movie_id);

-- The rating_events queue referenced in section 16.7 as the fallback for
-- "very popular" movies: instead of updating movies synchronously, the
-- endpoint inserts a small event row and a background job rolls the events
-- up into rating_count/rating_sum. We don't materialize this table by
-- default for chapter 16 (the in-line incremental update is the pattern
-- this chapter teaches), but the schema below is what the section refers
-- to. Uncomment to use, or build the full version alongside the outbox
-- pattern in chapter 17.
--
-- CREATE TABLE IF NOT EXISTS rating_events (
--     id            BIGSERIAL PRIMARY KEY,
--     user_id       BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
--     movie_id      BIGINT      NOT NULL REFERENCES movies(id) ON DELETE CASCADE,
--     prev_score    SMALLINT,                    -- NULL when this is a brand-new rating
--     new_score     SMALLINT    NOT NULL CHECK (new_score BETWEEN 1 AND 10),
--     applied_at    TIMESTAMPTZ,                 -- set when the roll-up job consumes the event
--     created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
-- );
-- CREATE INDEX IF NOT EXISTS idx_rating_events_unapplied
--     ON rating_events (created_at) WHERE applied_at IS NULL;

COMMIT;
