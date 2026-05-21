-- Cinetrack chapter-22 seed.
-- Small starter set. The replication tour generates its own write volume.
-- Re-runnable.

BEGIN;

TRUNCATE TABLE view_events, reviews, users, movies
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
FROM generate_series(1, 50) AS g;

INSERT INTO users (username, email)
SELECT
    format('user%s', g),
    format('user%s@cinetrack.test', g)
FROM generate_series(1, 25) AS g;

INSERT INTO reviews (user_id, movie_id, body)
SELECT
    ((g - 1) % 25) + 1,
    ((g * 13) % 50) + 1,
    'A first-pass review for the replication tour.'
FROM generate_series(1, 30) AS g;

COMMIT;

SELECT 'movies'  AS tbl, count(*) FROM movies
UNION ALL SELECT 'users',   count(*) FROM users
UNION ALL SELECT 'reviews', count(*) FROM reviews;
