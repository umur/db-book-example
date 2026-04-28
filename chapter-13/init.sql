-- Cinetrack chapter-13 schema.
-- Same shape as chapter-9, plus the search columns and indexes the FTS
-- chapter walks through. Search vectors are STORED generated columns so
-- inserts and updates maintain them automatically.

BEGIN;

ALTER DATABASE cinetrack SET default_text_search_config = 'english';

CREATE TABLE IF NOT EXISTS movies (
    id            BIGSERIAL PRIMARY KEY,
    title         TEXT        NOT NULL,
    release_year  INT         NOT NULL,
    runtime_min   INT,
    director      TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- Weighted multi-column tsvector. Title gets weight A; director gets C.
    -- See section 13.4 for the pattern and 13.5 for what the weights buy us.
    search_tsv    tsvector
                  GENERATED ALWAYS AS (
                      setweight(to_tsvector('english', coalesce(title, '')),    'A') ||
                      setweight(to_tsvector('english', coalesce(director, '')), 'C')
                  ) STORED
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
    edited_at     TIMESTAMPTZ,
    -- Body-only vector at weight B. The chapter's combined-search example
    -- aggregates per-movie ranks from this column with title/director ranks
    -- from movies.search_tsv.
    search_tsv    tsvector
                  GENERATED ALWAYS AS (
                      setweight(to_tsvector('english', coalesce(body, '')), 'B')
                  ) STORED
);

CREATE TABLE IF NOT EXISTS watchlists (
    id            BIGSERIAL PRIMARY KEY,
    user_id       BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    movie_id      BIGINT      NOT NULL REFERENCES movies(id) ON DELETE CASCADE,
    added_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, movie_id)
);

-- Baseline B-tree from earlier chapters; useful for plans that filter by movie.
CREATE INDEX IF NOT EXISTS idx_reviews_movie_id ON reviews (movie_id);

-- The chapter's headline indexes.
-- GIN over the weighted tsvector columns powers full-text search.
-- fastupdate=off keeps the demo deterministic: every inserted row is
-- searchable immediately, no pending-list merge to wait on.
CREATE INDEX IF NOT EXISTS idx_movies_search_tsv
    ON movies USING GIN (search_tsv) WITH (fastupdate = off);

CREATE INDEX IF NOT EXISTS idx_reviews_search_tsv
    ON reviews USING GIN (search_tsv) WITH (fastupdate = off);

-- GIN trigram indexes power the fuzzy-fallback path.
-- gin_trgm_ops is what makes the % operator and similarity() index-supported.
CREATE INDEX IF NOT EXISTS idx_movies_title_trgm
    ON movies USING GIN (title gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_movies_director_trgm
    ON movies USING GIN (director gin_trgm_ops);

COMMIT;
