-- Cinetrack chapter-7 seed.
-- 50k movies, 5k users, 500k ratings, 200k reviews, 500k view_events.
-- The view_events table has correlated country_code and language_code,
-- which is the key data shape for the extended-statistics walkthrough.
--
-- Correlation rule: country -> language is near-functional.
--   US, GB, AU, CA -> en
--   FR             -> fr
--   DE, AT         -> de
--   ES, MX         -> es
--   JP             -> ja
--   TR             -> tr
-- A small percentage of rows break the rule on purpose, so the dependency
-- is strong but not perfect (real-world shape).

BEGIN;

TRUNCATE TABLE view_events, reviews, ratings, users, movies
RESTART IDENTITY CASCADE;

INSERT INTO movies (title, release_year, runtime_min, director)
SELECT
    format('Cinetrack Test Movie %s', g),
    1970 + (g % 55),
    80 + (g * 7) % 100,
    CASE (g % 8)
        WHEN 0 THEN 'A. Reiner'
        WHEN 1 THEN 'B. Coen'
        WHEN 2 THEN 'C. Nolan'
        WHEN 3 THEN 'D. Villeneuve'
        WHEN 4 THEN 'E. Park'
        WHEN 5 THEN 'F. Bigelow'
        WHEN 6 THEN 'G. Kurosawa'
        WHEN 7 THEN 'H. Lee'
    END
FROM generate_series(1, 50000) AS g;

INSERT INTO users (username, email)
SELECT
    format('user%s', g),
    format('user%s@cinetrack.test', g)
FROM generate_series(1, 5000) AS g;

INSERT INTO ratings (user_id, movie_id, score)
SELECT DISTINCT ON (u, m) u, m, ((u * 7 + m * 3) % 10) + 1
FROM (
    SELECT
        ((g - 1) % 5000) + 1                    AS u,
        ((g * 17) % 50000) + 1                  AS m
    FROM generate_series(1, 700000) AS g
) s(u, m)
LIMIT 500000;

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
    now() - (g || ' seconds')::interval
FROM generate_series(1, 200000) AS g;

-- view_events with correlated country_code and language_code.
-- 5% of rows have a "noisy" language that breaks the dependency rule,
-- so the extended-statistics demonstration shows a real but imperfect
-- functional dependency, which is the realistic case.
INSERT INTO view_events (user_id, movie_id, duration_sec, occurred_at,
                         country_code, language_code)
SELECT
    ((g - 1) % 5000) + 1                            AS user_id,
    ((g * 19) % 50000) + 1                          AS movie_id,
    600 + (g % 6000)                                AS duration_sec,
    now() - (g || ' seconds')::interval             AS occurred_at,
    cc                                              AS country_code,
    CASE
        WHEN g % 20 = 0 THEN
            -- 5% noise: a language that doesn't match the country
            (ARRAY['en','fr','de','es','ja','tr'])[((g * 7) % 6) + 1]
        ELSE
            CASE cc
                WHEN 'US' THEN 'en'
                WHEN 'GB' THEN 'en'
                WHEN 'AU' THEN 'en'
                WHEN 'CA' THEN 'en'
                WHEN 'FR' THEN 'fr'
                WHEN 'DE' THEN 'de'
                WHEN 'AT' THEN 'de'
                WHEN 'ES' THEN 'es'
                WHEN 'MX' THEN 'es'
                WHEN 'JP' THEN 'ja'
                WHEN 'TR' THEN 'tr'
            END
    END                                             AS language_code
FROM (
    SELECT g,
           CASE
               WHEN g %  100 < 40 THEN 'US'
               WHEN g %  100 < 55 THEN 'GB'
               WHEN g %  100 < 65 THEN 'CA'
               WHEN g %  100 < 70 THEN 'AU'
               WHEN g %  100 < 78 THEN 'FR'
               WHEN g %  100 < 85 THEN 'DE'
               WHEN g %  100 < 88 THEN 'AT'
               WHEN g %  100 < 92 THEN 'ES'
               WHEN g %  100 < 95 THEN 'MX'
               WHEN g %  100 < 98 THEN 'JP'
               ELSE                    'TR'
           END AS cc
    FROM generate_series(1, 500000) AS g
) seed;

COMMIT;

ANALYZE;

SELECT 'movies'         AS tbl, count(*) FROM movies
UNION ALL SELECT 'users',          count(*) FROM users
UNION ALL SELECT 'ratings',        count(*) FROM ratings
UNION ALL SELECT 'reviews',        count(*) FROM reviews
UNION ALL SELECT 'view_events',    count(*) FROM view_events;
