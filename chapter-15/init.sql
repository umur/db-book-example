-- Cinetrack chapter-15 schema.
-- Same shape as chapter-1: enough tables to demo isolation and locking.
-- The chapter focuses on ratings (lost-update demos), reviews (write skew),
-- and movies (quota counter). Other tables are present for context.

BEGIN;

CREATE TABLE IF NOT EXISTS movies (
    id            BIGSERIAL PRIMARY KEY,
    title         TEXT        NOT NULL,
    release_year  INT         NOT NULL,
    runtime_min   INT,
    director      TEXT,
    quota         INT         NOT NULL DEFAULT 10,
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
    featured      BOOLEAN     NOT NULL DEFAULT false,
    rated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, movie_id)
);

CREATE TABLE IF NOT EXISTS reviews (
    id            BIGSERIAL PRIMARY KEY,
    user_id       BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    movie_id      BIGINT      NOT NULL REFERENCES movies(id) ON DELETE CASCADE,
    body          TEXT        NOT NULL,
    posted_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    edited_at     TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_movies_release_year   ON movies (release_year);
CREATE INDEX IF NOT EXISTS idx_ratings_movie_id      ON ratings (movie_id);
CREATE INDEX IF NOT EXISTS idx_reviews_movie_id      ON reviews (movie_id);

COMMIT;
