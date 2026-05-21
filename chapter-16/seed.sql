-- Cinetrack chapter-16 seed.
-- Re-runnable. TRUNCATE first, then insert.
-- Same volumes as chapter-2, plus a small set of pending jobs for the queue tour.

BEGIN;

TRUNCATE TABLE idempotency_keys, jobs, notifications, reviews, ratings, users, movies
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

-- Backfill the rating aggregates so optimistic-update demos start from a
-- realistic baseline.
UPDATE movies m
SET rating_count = sub.cnt,
    rating_sum   = sub.total
FROM (
    SELECT movie_id, count(*) AS cnt, sum(score) AS total
    FROM ratings
    GROUP BY movie_id
) sub
WHERE m.id = sub.movie_id;

-- Twenty pending jobs for the SKIP LOCKED tour.
INSERT INTO jobs (payload)
SELECT jsonb_build_object(
    'kind',  'send_notification',
    'user',  ((g - 1) % 50) + 1,
    'body',  format('You have %s new replies', g)
)
FROM generate_series(1, 20) AS g;

COMMIT;

SELECT 'movies'           AS tbl, count(*) FROM movies
UNION ALL SELECT 'users',           count(*) FROM users
UNION ALL SELECT 'ratings',         count(*) FROM ratings
UNION ALL SELECT 'reviews',         count(*) FROM reviews
UNION ALL SELECT 'jobs',            count(*) FROM jobs
UNION ALL SELECT 'idempotency_keys',count(*) FROM idempotency_keys;
