-- Cinetrack chapter-15 seed.
-- 100 movies, 50 users, ~500 ratings, 50 reviews. Re-runnable.

BEGIN;

TRUNCATE TABLE reviews, ratings, users, movies RESTART IDENTITY CASCADE;

INSERT INTO movies (title, release_year, runtime_min, director, quota)
SELECT
    format('Cinetrack Test Movie %s', g),
    1970 + (g % 55),
    80 + (g * 7) % 100,
    CASE (g % 4)
        WHEN 0 THEN 'A. Reiner'
        WHEN 1 THEN 'B. Coen'
        WHEN 2 THEN 'C. Nolan'
        WHEN 3 THEN 'D. Villeneuve'
    END,
    10
FROM generate_series(1, 100) AS g;

INSERT INTO users (username, email)
SELECT
    format('user%s', g),
    format('user%s@cinetrack.test', g)
FROM generate_series(1, 50) AS g;

INSERT INTO ratings (user_id, movie_id, score)
SELECT DISTINCT ON (u, m) u, m, ((u * 7 + m * 3) % 10) + 1
FROM (
    SELECT
        ((g - 1) % 50) + 1                    AS u,
        ((g * 17) % 100) + 1                  AS m
    FROM generate_series(1, 600) AS g
) s(u, m);

INSERT INTO reviews (user_id, movie_id, body)
SELECT
    ((g - 1) % 50) + 1,
    ((g * 13) % 100) + 1,
    CASE (g % 5)
        WHEN 0 THEN 'A slow burn that rewards patience.'
        WHEN 1 THEN 'Too long by half, but the third act lands.'
        WHEN 2 THEN 'Stunning cinematography. Story is fine.'
        WHEN 3 THEN 'I expected to hate this. I did not.'
        WHEN 4 THEN 'Will not watch again. Will not forget.'
    END
FROM generate_series(1, 50) AS g;

COMMIT;

SELECT 'movies'  AS tbl, count(*) FROM movies
UNION ALL SELECT 'users',   count(*) FROM users
UNION ALL SELECT 'ratings', count(*) FROM ratings
UNION ALL SELECT 'reviews', count(*) FROM reviews;
