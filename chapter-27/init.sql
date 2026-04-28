-- Cinetrack chapter-27 schema.
-- Same shape as chapter-5, sized to fit the tuning tour. The tour wants
-- enough rows to make plan changes from work_mem and effective_cache_size
-- visible without needing a multi-gigabyte seed.

-- pg_buffercache is created here (as superuser, during container init) so
-- section (10) of the tuning tour can read the buffer cache without
-- escalating privileges later.
CREATE EXTENSION IF NOT EXISTS pg_buffercache;

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

CREATE TABLE IF NOT EXISTS view_events (
    id            BIGSERIAL PRIMARY KEY,
    user_id       BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    movie_id      BIGINT      NOT NULL REFERENCES movies(id) ON DELETE CASCADE,
    occurred_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    duration_sec  INT
);

CREATE INDEX IF NOT EXISTS idx_movies_release_year     ON movies (release_year);
CREATE INDEX IF NOT EXISTS idx_ratings_movie_id        ON ratings (movie_id);
CREATE INDEX IF NOT EXISTS idx_view_events_occurred_at ON view_events (occurred_at);
CREATE INDEX IF NOT EXISTS idx_view_events_user_id     ON view_events (user_id);

COMMIT;
