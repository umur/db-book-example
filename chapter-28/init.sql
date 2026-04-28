-- Chapter 28 sandbox schema. The same cinetrack tables we have used
-- through the book, plus the bits the runbooks need to be
-- reproducible: a replication user, a slot, and pg_stat_statements.

CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Replication user used by the standby in runbooks/replication-broke.md.
-- The password is intentionally hardcoded for the sandbox.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'replicator') THEN
        CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'replicator';
    END IF;
END $$;

-- Allow the replicator role to connect from the docker network. This
-- mirrors a typical pg_hba.conf entry and is configured here so the
-- sandbox can be reproduced without editing pg_hba.conf by hand.
-- (postgres:17-alpine reads pg_hba.conf from the data dir; the
-- entrypoint script copies a default pg_hba.conf with `host
-- replication all all md5` already enabled, so this DO block is the
-- only step needed.)

CREATE TABLE IF NOT EXISTS movies (
    id          BIGSERIAL PRIMARY KEY,
    title       TEXT        NOT NULL,
    released    DATE        NOT NULL
);

CREATE TABLE IF NOT EXISTS users (
    id          BIGSERIAL PRIMARY KEY,
    handle      TEXT        NOT NULL UNIQUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- The reviews table is the one the runbooks pick on. Tuned so that the
-- vacuum-falling-behind runbook can reproduce bloat quickly with the
-- seed data plus an update loop.
CREATE TABLE IF NOT EXISTS reviews (
    id          BIGSERIAL PRIMARY KEY,
    user_id     BIGINT      NOT NULL REFERENCES users(id),
    movie_id    BIGINT      NOT NULL REFERENCES movies(id),
    body        TEXT        NOT NULL,
    rating      SMALLINT    NOT NULL CHECK (rating BETWEEN 1 AND 5),
    posted_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
)
WITH (
    autovacuum_vacuum_scale_factor = 0.05,
    autovacuum_analyze_scale_factor = 0.02
);

CREATE INDEX IF NOT EXISTS reviews_movie_idx
    ON reviews (movie_id, posted_at DESC);

-- A view_events table the slow.md runbook uses to demonstrate a
-- sequential-scan regression after a missing-index incident.
CREATE TABLE IF NOT EXISTS view_events (
    id          BIGSERIAL PRIMARY KEY,
    user_id     BIGINT      NOT NULL,
    movie_id    BIGINT      NOT NULL,
    viewed_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
