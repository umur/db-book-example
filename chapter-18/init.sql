-- Cinetrack chapter-18 schema.
-- Same shape as earlier chapters, focused on reviews for the vacuum tour.
-- The reviews table here intentionally ships with default autovacuum settings
-- so the chapter can demonstrate how per-table tuning improves things.

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

-- The hot table for this chapter. Update-heavy: edits, status flags,
-- moderation actions all touch it. Body and edited_at are unindexed so
-- updates are HOT-eligible. movie_id is indexed so updates that change
-- it are non-HOT (good for the HOT vs non-HOT demo in the tour).
CREATE TABLE IF NOT EXISTS reviews (
    id            BIGSERIAL PRIMARY KEY,
    user_id       BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    movie_id      BIGINT      NOT NULL REFERENCES movies(id) ON DELETE CASCADE,
    body          TEXT        NOT NULL,
    status        TEXT        NOT NULL DEFAULT 'visible'
                  CHECK (status IN ('visible', 'flagged', 'hidden')),
    posted_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    edited_at     TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_movies_release_year ON movies (release_year);
CREATE INDEX IF NOT EXISTS idx_reviews_movie_id    ON reviews (movie_id);
CREATE INDEX IF NOT EXISTS idx_reviews_user_id     ON reviews (user_id);
CREATE INDEX IF NOT EXISTS idx_reviews_status      ON reviews (status)
    WHERE status <> 'visible';

COMMIT;
