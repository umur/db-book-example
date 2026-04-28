-- Chapter 25 sandbox schema. Tiny on purpose: the chapter is about HA
-- mechanics, not data modeling. The cinetrack reviews table is enough
-- to demonstrate writes against the primary, lag on the replicas, and
-- timeline switches across failovers.

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

CREATE TABLE IF NOT EXISTS reviews (
    id          BIGSERIAL PRIMARY KEY,
    user_id     BIGINT      NOT NULL REFERENCES users(id),
    movie_id    BIGINT      NOT NULL REFERENCES movies(id),
    body        TEXT        NOT NULL,
    posted_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS reviews_movie_idx
    ON reviews (movie_id, posted_at DESC);

-- A heartbeat table the failover-tour uses to demonstrate lossless sync
-- replication. Each row is one INSERT; we count rows before and after
-- the failover to prove zero data loss.
CREATE TABLE IF NOT EXISTS heartbeat (
    id          BIGSERIAL PRIMARY KEY,
    written_at  TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    written_by  TEXT        NOT NULL DEFAULT inet_server_addr()::text
);
