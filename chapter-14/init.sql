-- Cinetrack chapter-14 schema.
-- Same core shape as earlier chapters, plus the view_events tables the
-- partitioning chapter walks through. Two versions ship side by side:
--
--   view_events_legacy : single unpartitioned table, the "before" state
--   view_events        : declarative-RANGE-partitioned table, the "after"
--
-- The seed script populates both with ~1M rows spread across 12+ months
-- so EXPLAIN plans show realistic partition pruning behavior.

BEGIN;

ALTER DATABASE cinetrack SET default_text_search_config = 'english';

CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Core tables (same shape as earlier chapters, narrowed types per 14.2).
CREATE TABLE IF NOT EXISTS movies (
    id            BIGSERIAL PRIMARY KEY,
    title         TEXT        NOT NULL,
    release_year  SMALLINT    NOT NULL CHECK (release_year BETWEEN 1888 AND 2100),
    runtime_min   SMALLINT    CHECK (runtime_min IS NULL OR runtime_min BETWEEN 1 AND 600),
    director      TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS users (
    id            BIGSERIAL PRIMARY KEY,
    username      TEXT        NOT NULL UNIQUE
                              CHECK (length(username) BETWEEN 3 AND 50),
    email         TEXT        NOT NULL UNIQUE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Ratings: composite uniqueness, the shape from 14.3.
CREATE TABLE IF NOT EXISTS ratings (
    id            BIGSERIAL PRIMARY KEY,
    user_id       BIGINT      NOT NULL REFERENCES users(id)  ON DELETE CASCADE,
    movie_id      BIGINT      NOT NULL REFERENCES movies(id) ON DELETE CASCADE,
    score         SMALLINT    NOT NULL CHECK (score BETWEEN 1 AND 10),
    rated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, movie_id)
);

-- Reviews carry a STORED generated tsvector to demo 14.4 alongside FTS.
CREATE TABLE IF NOT EXISTS reviews (
    id            BIGSERIAL PRIMARY KEY,
    user_id       BIGINT      NOT NULL REFERENCES users(id)  ON DELETE CASCADE,
    movie_id      BIGINT      NOT NULL REFERENCES movies(id) ON DELETE CASCADE,
    body          TEXT        NOT NULL CHECK (length(body) BETWEEN 1 AND 10000),
    posted_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    edited_at     TIMESTAMPTZ,
    body_length   INT         GENERATED ALWAYS AS (length(body)) STORED,
    search_tsv    tsvector
                  GENERATED ALWAYS AS (
                      to_tsvector('english', coalesce(body, ''))
                  ) STORED
);

CREATE INDEX IF NOT EXISTS idx_reviews_movie_id    ON reviews (movie_id);
CREATE INDEX IF NOT EXISTS idx_reviews_search_tsv  ON reviews USING GIN (search_tsv);

-- Watchlists: a per-user list of movies someone plans to watch. The seed
-- script truncates this alongside the other user-owned tables, so the
-- table needs to exist before seed.sql runs.
CREATE TABLE IF NOT EXISTS watchlists (
    user_id   BIGINT      NOT NULL REFERENCES users(id)  ON DELETE CASCADE,
    movie_id  BIGINT      NOT NULL REFERENCES movies(id) ON DELETE CASCADE,
    added_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, movie_id)
);

-- EXCLUDE constraint demo (14.3): a screen cannot have overlapping bookings.
CREATE TABLE IF NOT EXISTS screen_bookings (
    id        BIGSERIAL PRIMARY KEY,
    screen_id BIGINT    NOT NULL,
    booking   TSTZRANGE NOT NULL,
    EXCLUDE USING GIST (
        screen_id WITH =,
        booking   WITH &&
    )
);

-- ----------------------------------------------------------------------
-- view_events_legacy: the "before" state. Single big table, three indexes,
-- the shape every team ships first. The partitioning tour compares plans
-- against this.
-- ----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS view_events_legacy (
    id          BIGSERIAL PRIMARY KEY,
    user_id     BIGINT      NOT NULL REFERENCES users(id),
    movie_id    BIGINT      NOT NULL REFERENCES movies(id),
    seconds     INT         NOT NULL CHECK (seconds BETWEEN 0 AND 86400),
    completed   BOOLEAN     NOT NULL DEFAULT FALSE,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_view_events_legacy_user
    ON view_events_legacy (user_id);
CREATE INDEX IF NOT EXISTS idx_view_events_legacy_movie
    ON view_events_legacy (movie_id);
CREATE INDEX IF NOT EXISTS idx_view_events_legacy_occurred
    ON view_events_legacy (occurred_at);

-- ----------------------------------------------------------------------
-- view_events: the partitioned shape. RANGE-partitioned by occurred_at.
-- The PK includes the partitioning column (see 14.6 for why).
-- Indexes declared here propagate to every child partition automatically.
-- ----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS view_events (
    id          BIGSERIAL,
    user_id     BIGINT      NOT NULL REFERENCES users(id),
    movie_id    BIGINT      NOT NULL REFERENCES movies(id),
    seconds     INT         NOT NULL CHECK (seconds BETWEEN 0 AND 86400),
    completed   BOOLEAN     NOT NULL DEFAULT FALSE,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (id, occurred_at)
) PARTITION BY RANGE (occurred_at);

CREATE INDEX IF NOT EXISTS idx_view_events_user
    ON view_events (user_id);
CREATE INDEX IF NOT EXISTS idx_view_events_movie
    ON view_events (movie_id);

-- Create one partition per month for the last 13 months (12 historical
-- plus the current month). Naming pattern: view_events_YYYY_MM.
DO $$
DECLARE
    m DATE;
BEGIN
    FOR m IN
        SELECT generate_series(
            date_trunc('month', now()) - interval '12 months',
            date_trunc('month', now()),
            interval '1 month'
        )::date
    LOOP
        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS view_events_%s
             PARTITION OF view_events
             FOR VALUES FROM (%L) TO (%L)',
            to_char(m, 'YYYY_MM'),
            m,
            m + interval '1 month'
        );
    END LOOP;
END$$;

-- Default partition catches mis-ranged rows during migrations or clock skew.
-- Production tables with strict retention should NOT use a default partition;
-- the cinetrack sandbox uses one to keep the demo forgiving.
CREATE TABLE IF NOT EXISTS view_events_default
    PARTITION OF view_events DEFAULT;

COMMIT;
