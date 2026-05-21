-- Cinetrack chapter-23 seed.
-- Smaller starter: the streaming-tour.sql script generates additional
-- write traffic on the primary so the lag and conflict experiments
-- have something to show.

BEGIN;

TRUNCATE TABLE view_events, reviews, ratings, users, movies
RESTART IDENTITY CASCADE;

INSERT INTO movies (title, release_year, runtime_min, director)
SELECT
    format('Cinetrack Test Movie %s', g),
    1970 + (g % 55),
    80 + (g * 7) % 100,
    CASE (g % 4)
        WHEN 0 THEN 'A. Reiner'
        WHEN 1 THEN 'C. Nolan'
        WHEN 2 THEN 'D. Villeneuve'
        WHEN 3 THEN 'G. Kurosawa'
    END
FROM generate_series(1, 100) AS g;

INSERT INTO users (username, email)
SELECT
    format('user%s', g),
    format('user%s@cinetrack.test', g)
FROM generate_series(1, 50) AS g;

INSERT INTO reviews (user_id, movie_id, body)
SELECT
    ((g - 1) % 50) + 1,
    ((g * 13) % 100) + 1,
    'A first-pass review for the streaming tour.'
FROM generate_series(1, 200) AS g;

INSERT INTO ratings (user_id, movie_id, score)
SELECT
    ((g - 1) % 50) + 1,
    ((g * 7)  % 100) + 1,
    1 + (g % 10)
FROM generate_series(1, 200) AS g
ON CONFLICT (user_id, movie_id) DO NOTHING;

COMMIT;

SELECT 'movies'      AS tbl, count(*) FROM movies
UNION ALL SELECT 'users',     count(*) FROM users
UNION ALL SELECT 'reviews',   count(*) FROM reviews
UNION ALL SELECT 'ratings',   count(*) FROM ratings;
