-- Cinetrack chapter-8 seed.
-- ~50,000 movies, ~5,000 users, ~500,000 ratings, ~500,000 reviews.
-- Large enough to make EXPLAIN walkthroughs feel like production.
-- Re-runnable: TRUNCATE first, then insert.

BEGIN;

TRUNCATE TABLE reviews, ratings, users, movies RESTART IDENTITY CASCADE;

-- Movies. Title prefixes are deliberately skewed: about 18% start with 'The '
-- to make the prefix-LIKE walkthrough behave realistically.
INSERT INTO movies (title, release_year, runtime_min, director)
SELECT
    CASE (g % 11)
        WHEN 0 THEN format('The %s of Cinetrack',  g)
        WHEN 1 THEN format('The %s and the %s',    g, (g * 7) % 100)
        WHEN 2 THEN format('A Story of %s',        g)
        WHEN 3 THEN format('Cinetrack %s',         g)
        WHEN 4 THEN format('Movie %s',             g)
        WHEN 5 THEN format('Stories from %s',      g)
        WHEN 6 THEN format('Echoes of %s',         g)
        WHEN 7 THEN format('Quiet %s',             g)
        WHEN 8 THEN format('Beyond %s',            g)
        WHEN 9 THEN format('Notes on %s',          g)
        ELSE        format('Untitled %s',          g)
    END,
    1970 + (g % 56),
    80 + (g * 7) % 100,
    format('Director %s', (g % 200) + 1)
FROM generate_series(1, 50000) AS g;

-- Users.
INSERT INTO users (username, email)
SELECT
    format('user%s', g),
    format('user%s@cinetrack.test', g)
FROM generate_series(1, 5000) AS g;

-- Ratings: ~500,000 rows. Distribution is skewed by user and by movie so the
-- planner has something interesting to estimate.
INSERT INTO ratings (user_id, movie_id, score, rated_at)
SELECT
    ((g - 1) % 5000) + 1                        AS user_id,
    ((g * 17) % 50000) + 1                      AS movie_id,
    ((g * 7) % 10) + 1                          AS score,
    now() - (g % 1000 || ' hours')::interval    AS rated_at
FROM generate_series(1, 500000) AS g;

-- Reviews: ~500,000 rows. Same scale as ratings so the join walkthroughs
-- in section 8.8 (Seq Scan filtered by user_id) reproduce reliably.
INSERT INTO reviews (user_id, movie_id, body, posted_at)
SELECT
    ((g - 1) % 5000) + 1,
    ((g * 13) % 50000) + 1,
    CASE (g % 5)
        WHEN 0 THEN 'A slow burn that rewards patience.'
        WHEN 1 THEN 'Too long by half, but the third act lands.'
        WHEN 2 THEN 'Stunning cinematography. Story is fine.'
        WHEN 3 THEN 'I expected to hate this. I did not.'
        WHEN 4 THEN 'Will not watch again. Will not forget.'
    END,
    now() - (g % 720 || ' hours')::interval
FROM generate_series(1, 500000) AS g;

COMMIT;

ANALYZE movies;
ANALYZE users;
ANALYZE ratings;
ANALYZE reviews;

SELECT 'movies'  AS tbl, count(*) FROM movies
UNION ALL SELECT 'users',   count(*) FROM users
UNION ALL SELECT 'ratings', count(*) FROM ratings
UNION ALL SELECT 'reviews', count(*) FROM reviews;
