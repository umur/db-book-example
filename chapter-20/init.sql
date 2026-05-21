-- Cinetrack chapter-20 schema.
-- Reuses the cinetrack core (movies, users, reviews, follows) at a size
-- where the home-feed regression in section 20.8 actually bites.

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

CREATE TABLE IF NOT EXISTS follows (
    follower_id   BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    followed_id   BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (follower_id, followed_id),
    CHECK (follower_id <> followed_id)
);

CREATE TABLE IF NOT EXISTS reviews (
    id            BIGSERIAL PRIMARY KEY,
    user_id       BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    movie_id      BIGINT      NOT NULL REFERENCES movies(id) ON DELETE CASCADE,
    body          TEXT        NOT NULL,
    posted_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes that exist BEFORE the regression in section 20.8.
-- The home-feed query is fast on the small table because the planner
-- picks an index nested loop. As the table grows, the planner flips to
-- a hash semijoin over a sequential scan and the query collapses.
-- The fix is the (user_id, posted_at DESC) composite added in 20.8.
CREATE INDEX IF NOT EXISTS idx_reviews_user_id    ON reviews (user_id);
CREATE INDEX IF NOT EXISTS idx_reviews_posted_at  ON reviews (posted_at DESC);
CREATE INDEX IF NOT EXISTS idx_follows_follower   ON follows (follower_id);

COMMIT;
