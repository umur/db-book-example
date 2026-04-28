-- Cinetrack chapter-24 schema.
-- Run this against both clusters: the Postgres 15 publisher and the
-- Postgres 17 subscriber. Logical replication does not ship DDL, so
-- the schema must already exist on the subscriber before CREATE
-- SUBSCRIPTION will succeed.
--
-- Same shape as the rest of Part III. Reviews carries a region column
-- so the row-filter demo in logical-tour.sql has something to filter on.

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
    region        TEXT        NOT NULL DEFAULT 'eu',
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
    region        TEXT        NOT NULL DEFAULT 'eu',
    posted_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_movies_release_year   ON movies (release_year);
CREATE INDEX IF NOT EXISTS idx_ratings_movie_id      ON ratings (movie_id);
CREATE INDEX IF NOT EXISTS idx_reviews_movie_id      ON reviews (movie_id);
CREATE INDEX IF NOT EXISTS idx_reviews_region        ON reviews (region);
CREATE INDEX IF NOT EXISTS idx_users_region          ON users  (region);

COMMIT;

-- A dedicated replication role on the publisher. The subscriber uses
-- this role to open the replication connection. REPLICATION privilege
-- is required to read the WAL stream.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'cinetrack_replica') THEN
        CREATE ROLE cinetrack_replica
            LOGIN REPLICATION PASSWORD 'cinetrack_replica';
    END IF;
END$$;

GRANT USAGE ON SCHEMA public TO cinetrack_replica;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO cinetrack_replica;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT ON TABLES TO cinetrack_replica;
