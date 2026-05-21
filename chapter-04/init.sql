-- Cinetrack chapter-4 schema.
-- Same shape as chapter-2: enough tables to run a credible write workload
-- against. The chapter focuses on the WAL itself, not on schema design.

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
    duration_sec  INT
);

CREATE INDEX IF NOT EXISTS idx_reviews_movie_id     ON reviews (movie_id);
CREATE INDEX IF NOT EXISTS idx_view_events_occurred ON view_events (occurred_at);

COMMIT;
