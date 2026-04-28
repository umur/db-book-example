-- Cinetrack chapter-22 schema.
-- Same shape as earlier chapters. The chapter focuses on replication, not on
-- schema design.

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

-- The replication role used by pg_basebackup and the standby's streaming
-- connection. REPLICATION is the only attribute the protocol needs.
--
-- Note: the official postgres image creates the user named in
-- POSTGRES_USER (cinetrack) as a SUPERUSER. The chapter at 22.3
-- explicitly warns against giving the replication role superuser. The
-- sandbox uses the cinetrack SUPERUSER for replication for simplicity.
-- In production, create a dedicated replicator role with WITH REPLICATION
-- LOGIN only and connect the standby with that role.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'cinetrack') THEN
        CREATE ROLE cinetrack WITH REPLICATION LOGIN PASSWORD 'cinetrack';
    ELSE
        ALTER ROLE cinetrack WITH REPLICATION LOGIN;
    END IF;
END $$;

COMMIT;
