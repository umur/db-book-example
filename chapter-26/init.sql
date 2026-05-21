-- Chapter 26 sandbox schema. The cinetrack reviews table is enough to
-- demonstrate a destructive DELETE and a recovery to one second before
-- it. The schema is intentionally small; the chapter is about backup
-- mechanics, not data modeling.

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

-- An audit table the walkthrough writes to between the base backup and
-- the destructive DELETE, so the recovery can be checked with row
-- counts instead of guessing.
CREATE TABLE IF NOT EXISTS audit_log (
    id          BIGSERIAL PRIMARY KEY,
    written_at  TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    note        TEXT        NOT NULL
);
