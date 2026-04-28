-- Cinetrack chapter-12 schema.
-- Hybrid pattern: real columns for the hot fields the application queries,
-- a JSONB tail for the variable, schemaless metadata.

BEGIN;

CREATE TABLE IF NOT EXISTS movies (
    id            BIGSERIAL   PRIMARY KEY,
    title         TEXT        NOT NULL,
    director      TEXT,
    release_year  INT,
    runtime_min   INT,
    rating_avg    NUMERIC(3,1),
    metadata      JSONB       NOT NULL DEFAULT '{}'::jsonb,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Surface-column indexes. The chapter-12 tour adds JSONB indexes
-- interactively so EXPLAIN can show before/after plans.
CREATE INDEX IF NOT EXISTS idx_movies_year
    ON movies (release_year);

CREATE INDEX IF NOT EXISTS idx_movies_director
    ON movies (director);

COMMIT;
