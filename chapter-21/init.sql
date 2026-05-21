-- Cinetrack chapter-21 schema.
-- Same shape as the rest of Part III: enough tables to demo the
-- zero-downtime migration patterns. The chapter's anchor case study is
-- renaming reviews.body to reviews.content under live load, so reviews
-- is the focal table.
--
-- A dedicated migration role is created so we can show the
-- ALTER ROLE ... SET lock_timeout pattern from subchapter 21.3.

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

CREATE TABLE IF NOT EXISTS ratings (
    id            BIGSERIAL PRIMARY KEY,
    user_id       BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    movie_id      BIGINT      NOT NULL REFERENCES movies(id) ON DELETE CASCADE,
    score         SMALLINT    NOT NULL CHECK (score BETWEEN 1 AND 10),
    rated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, movie_id)
);

-- The starting state. body is the column we will rename to content,
-- and there is no flagged column yet. The migrations directory walks
-- through each safe pattern.
CREATE TABLE IF NOT EXISTS reviews (
    id            BIGSERIAL PRIMARY KEY,
    user_id       BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    movie_id      BIGINT      NOT NULL REFERENCES movies(id) ON DELETE CASCADE,
    body          TEXT        NOT NULL,
    posted_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_movies_release_year   ON movies (release_year);
CREATE INDEX IF NOT EXISTS idx_ratings_movie_id      ON ratings (movie_id);
CREATE INDEX IF NOT EXISTS idx_reviews_movie_id      ON reviews (movie_id);

COMMIT;

-- Migration role: a dedicated user with role-level lock_timeout so any
-- migration run as this user has a safe floor even if the script forgets
-- the SET LOCAL.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'cinetrack_migrator') THEN
        CREATE ROLE cinetrack_migrator LOGIN PASSWORD 'cinetrack_migrator';
    END IF;
END$$;

GRANT ALL ON SCHEMA public TO cinetrack_migrator;
GRANT ALL ON ALL TABLES IN SCHEMA public TO cinetrack_migrator;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO cinetrack_migrator;

ALTER ROLE cinetrack_migrator SET lock_timeout = '5s';
ALTER ROLE cinetrack_migrator SET statement_timeout = '0';
