-- Cinetrack chapter-19 seed.
-- Modest volume: 200 movies, 1,000 users, 8,000 ratings.
-- The chapter is about pooling, not query plans, so the data set is small.

BEGIN;

TRUNCATE TABLE ratings, users, movies RESTART IDENTITY CASCADE;

INSERT INTO movies (title, release_year, runtime_min, director)
SELECT
    format('Cinetrack Test Movie %s', g),
    1980 + (g % 45),
    85 + (g * 11) % 90,
    CASE (g % 6)
        WHEN 0 THEN 'A. Reiner'
        WHEN 1 THEN 'B. Coen'
        WHEN 2 THEN 'C. Nolan'
        WHEN 3 THEN 'D. Villeneuve'
        WHEN 4 THEN 'E. Park'
        WHEN 5 THEN 'F. Bigelow'
    END
FROM generate_series(1, 200) AS g;

INSERT INTO users (username, email)
SELECT
    format('user%s', g),
    format('user%s@cinetrack.test', g)
FROM generate_series(1, 1000) AS g;

INSERT INTO ratings (user_id, movie_id, score)
SELECT DISTINCT ON (u, m) u, m, ((u * 7 + m * 3) % 10) + 1
FROM (
    SELECT
        ((g - 1) % 1000) + 1 AS u,
        ((g * 17) % 200) + 1 AS m
    FROM generate_series(1, 8000) AS g
) s(u, m);

COMMIT;

ANALYZE;

SELECT 'movies'  AS tbl, count(*) FROM movies
UNION ALL SELECT 'users',  count(*) FROM users
UNION ALL SELECT 'ratings', count(*) FROM ratings;
