-- Cinetrack chapter-11 schema.
-- Sized for the joins tour: enough rows that nested loops vs hash joins
-- produce visibly different runtimes. Same column shapes as earlier chapters.

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
    id              BIGSERIAL PRIMARY KEY,
    username        TEXT        NOT NULL UNIQUE,
    email           TEXT        NOT NULL UNIQUE,
    last_login_at   TIMESTAMPTZ,
    deleted_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS ratings (
    id            BIGSERIAL PRIMARY KEY,
    user_id       BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    movie_id      BIGINT      NOT NULL REFERENCES movies(id) ON DELETE CASCADE,
    score         SMALLINT    NOT NULL CHECK (score BETWEEN 1 AND 10),
    rated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS reviews (
    id            BIGSERIAL PRIMARY KEY,
    user_id       BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    movie_id      BIGINT      NOT NULL REFERENCES movies(id) ON DELETE CASCADE,
    body          TEXT        NOT NULL,
    posted_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    edited_at     TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS view_events (
    id            BIGSERIAL PRIMARY KEY,
    user_id       BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    movie_id      BIGINT      NOT NULL REFERENCES movies(id) ON DELETE CASCADE,
    occurred_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    session_length INT
);

-- Indexes that the chapter-11 tour assumes exist.
-- The tour creates a few more interactively to demonstrate plan flips.
CREATE INDEX IF NOT EXISTS idx_ratings_movie_id   ON ratings (movie_id);
CREATE INDEX IF NOT EXISTS idx_ratings_user_id    ON ratings (user_id);
CREATE INDEX IF NOT EXISTS idx_reviews_movie_id   ON reviews (movie_id);
CREATE INDEX IF NOT EXISTS idx_view_events_user_t ON view_events (user_id, occurred_at);
CREATE INDEX IF NOT EXISTS idx_movies_release_year ON movies (release_year);

COMMIT;
