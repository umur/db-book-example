-- Cinetrack chapter-27 seed.
-- 1,000 movies, 10,000 users, 30,000 ratings, 300,000 view_events.
-- Sized to make the tuning-tour plan changes visible: large enough that
-- random_page_cost shifts plans, small enough to load in under a minute.

BEGIN;

TRUNCATE TABLE view_events, ratings, users, movies RESTART IDENTITY CASCADE;

INSERT INTO movies (title, release_year, runtime_min, director)
SELECT
    format('Cinetrack Movie %s', g),
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
FROM generate_series(1, 1000) AS g;

INSERT INTO users (username, email)
SELECT
    format('user%s', g),
    format('user%s@cinetrack.test', g)
FROM generate_series(1, 10000) AS g;

INSERT INTO ratings (user_id, movie_id, score)
SELECT DISTINCT ON (u, m) u, m, ((u * 7 + m * 3) % 10) + 1
FROM (
    SELECT
        ((g - 1) % 10000) + 1                 AS u,
        ((g * 17) % 1000) + 1                 AS m
    FROM generate_series(1, 50000) AS g
) s(u, m);

INSERT INTO view_events (user_id, movie_id, duration_sec, occurred_at)
SELECT
    ((g - 1) % 10000) + 1,
    ((g * 19) % 1000) + 1,
    600 + (g % 6000),
    now() - (g || ' seconds')::interval
FROM generate_series(1, 300000) AS g;

COMMIT;

ANALYZE;

SELECT 'movies'      AS tbl, count(*) FROM movies
UNION ALL SELECT 'users',       count(*) FROM users
UNION ALL SELECT 'ratings',     count(*) FROM ratings
UNION ALL SELECT 'view_events', count(*) FROM view_events;
