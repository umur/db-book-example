-- Cinetrack chapter-9 schema.
-- Bigger than chapter-2: the indexing tour wants enough rows that bad
-- indexes are visibly slow. Same shape, same column names.

BEGIN;

CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TABLE IF NOT EXISTS movies (
    id            BIGSERIAL PRIMARY KEY,
    title         TEXT        NOT NULL,
    release_year  INT         NOT NULL,
    runtime_min   INT,
    director      TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- The email column intentionally has no full-table UNIQUE constraint.
-- Section 9.4 builds a partial unique index on LOWER(email) WHERE
-- deleted_at IS NULL, which only makes sense if no broader uniqueness
-- rule already covers the column.
CREATE TABLE IF NOT EXISTS users (
    id            BIGSERIAL PRIMARY KEY,
    username      TEXT        NOT NULL UNIQUE,
    email         TEXT        NOT NULL,
    deleted_at    TIMESTAMPTZ,
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

CREATE TABLE IF NOT EXISTS watchlists (
    id            BIGSERIAL PRIMARY KEY,
    user_id       BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    movie_id      BIGINT      NOT NULL REFERENCES movies(id) ON DELETE CASCADE,
    added_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, movie_id)
);

CREATE TABLE IF NOT EXISTS notifications (
    id            BIGSERIAL PRIMARY KEY,
    user_id       BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    payload       JSONB       NOT NULL,
    status        TEXT        NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending', 'sent', 'failed')),
    delivered_at  TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS screen_bookings (
    id         BIGSERIAL PRIMARY KEY,
    screen_id  BIGINT NOT NULL,
    booking    TSTZRANGE NOT NULL,
    EXCLUDE USING GIST (
        screen_id WITH =,
        booking   WITH &&
    )
);

-- The chapter-9 walkthrough creates additional indexes interactively.
-- We pre-create only the constraint indexes (PRIMARY KEY, UNIQUE, EXCLUDE)
-- and the chapter-2 baseline so the tour can show before/after for the
-- ones the chapter is actually about.

CREATE INDEX IF NOT EXISTS idx_reviews_movie_id ON reviews (movie_id);

COMMIT;
