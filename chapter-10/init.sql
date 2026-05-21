-- Cinetrack chapter-10 schema.
-- Same shape as chapter-9, with two additions for the specialty tour:
--   movies.genres   TEXT[]      (GIN demo target)
--   movies.metadata JSONB       (GIN/jsonb_path_ops demo target)
--   view_events                 (BRIN demo target, ~10M rows from seed)
--   event_attributes            (bloom index demo target)

BEGIN;

-- Required by the EXCLUDE constraint on screen_bookings, which mixes
-- a btree-style equality (screen_id) with a GiST range-overlap operator.
CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TABLE IF NOT EXISTS movies (
    id            BIGSERIAL PRIMARY KEY,
    title         TEXT        NOT NULL,
    release_year  INT         NOT NULL,
    runtime_min   INT,
    director      TEXT,
    genres        TEXT[]      NOT NULL DEFAULT '{}',
    metadata      JSONB       NOT NULL DEFAULT '{}'::jsonb,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS users (
    id            BIGSERIAL PRIMARY KEY,
    username      TEXT        NOT NULL UNIQUE,
    email         TEXT        NOT NULL UNIQUE,
    deleted_at    TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS reviews (
    id            BIGSERIAL PRIMARY KEY,
    user_id       BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    movie_id      BIGINT      NOT NULL REFERENCES movies(id) ON DELETE CASCADE,
    body          TEXT        NOT NULL,
    posted_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS notifications (
    id            BIGSERIAL PRIMARY KEY,
    user_id       BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    payload       JSONB       NOT NULL,
    status        TEXT        NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending', 'sent', 'failed')),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- The BRIN demo target. Append-only by design, so event_at correlates with
-- the heap's physical order. The seed populates it from generate_series so
-- the table is large enough for BRIN's size win to show in pg_relation_size.
CREATE TABLE IF NOT EXISTS view_events (
    id        BIGSERIAL PRIMARY KEY,
    user_id   BIGINT      NOT NULL,
    movie_id  BIGINT      NOT NULL,
    event_at  TIMESTAMPTZ NOT NULL
);

-- The bloom demo target. Wide table with low-cardinality columns; queries
-- filter on arbitrary subsets.
CREATE TABLE IF NOT EXISTS event_attributes (
    event_id      BIGINT PRIMARY KEY,
    region        TEXT,
    device_class  TEXT,
    plan          TEXT,
    referrer      TEXT,
    browser       TEXT,
    os            TEXT
);

-- The GiST EXCLUDE demo target. Two reservations on the same screen cannot
-- overlap in time. The constraint index serves overlap queries too.
CREATE TABLE IF NOT EXISTS screen_bookings (
    id         BIGSERIAL PRIMARY KEY,
    screen_id  BIGINT NOT NULL,
    booking    TSTZRANGE NOT NULL,
    EXCLUDE USING GIST (
        screen_id WITH =,
        booking   WITH &&
    )
);

-- The Hash demo target. Opaque session token, looked up only by equality.
CREATE TABLE IF NOT EXISTS sessions (
    user_id     BIGINT NOT NULL,
    token       TEXT   NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at  TIMESTAMPTZ NOT NULL
);

COMMIT;
