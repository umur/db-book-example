-- Cinetrack chapter-24 seed.
-- Run only on the publisher. The subscriber will receive these rows via
-- the initial copy from CREATE SUBSCRIPTION.
--
-- 100 movies, 50 users (half EU, half US), 500 ratings, 200 reviews.
-- The region split makes the row-filter demo in logical-tour.sql produce
-- a visible difference between filtered and unfiltered subscribers.

BEGIN;

TRUNCATE TABLE reviews, ratings, users, movies RESTART IDENTITY CASCADE;

INSERT INTO movies (title, release_year, runtime_min, director)
SELECT
    format('Cinetrack Test Movie %s', g),
    1970 + (g % 55),
    80 + (g * 7) % 100,
    CASE (g % 4)
        WHEN 0 THEN 'A. Reiner'
        WHEN 1 THEN 'B. Coen'
        WHEN 2 THEN 'C. Nolan'
        WHEN 3 THEN 'D. Villeneuve'
    END
FROM generate_series(1, 100) AS g;

INSERT INTO users (username, email, region)
SELECT
    format('user%s', g),
    format('user%s@cinetrack.test', g),
    CASE WHEN g % 2 = 0 THEN 'eu' ELSE 'us' END
FROM generate_series(1, 50) AS g;

INSERT INTO ratings (user_id, movie_id, score)
SELECT DISTINCT ON (u, m) u, m, ((u * 7 + m * 3) % 10) + 1
FROM (
    SELECT
        ((g - 1) % 50) + 1                    AS u,
        ((g * 17) % 100) + 1                  AS m
    FROM generate_series(1, 600) AS g
) s(u, m);

INSERT INTO reviews (user_id, movie_id, body, region)
SELECT
    s.user_id,
    s.movie_id,
    s.body,
    u.region
FROM (
    SELECT
        ((g - 1) % 50) + 1                       AS user_id,
        ((g * 13) % 100) + 1                     AS movie_id,
        CASE (g % 6)
            WHEN 0 THEN 'A slow burn that rewards patience.'
            WHEN 1 THEN 'Too long by half, but the third act lands.'
            WHEN 2 THEN 'Stunning cinematography. Story is fine.'
            WHEN 3 THEN 'I expected to hate this. I did not.'
            WHEN 4 THEN 'Will not watch again. Will not forget.'
            WHEN 5 THEN 'Three stars for the score alone.'
        END                                      AS body
    FROM generate_series(1, 200) AS g
) s
JOIN users u ON u.id = s.user_id;

COMMIT;

SELECT 'movies'  AS tbl, count(*) FROM movies
UNION ALL SELECT 'users (eu)', count(*) FROM users WHERE region = 'eu'
UNION ALL SELECT 'users (us)', count(*) FROM users WHERE region = 'us'
UNION ALL SELECT 'ratings',    count(*) FROM ratings
UNION ALL SELECT 'reviews',    count(*) FROM reviews;
