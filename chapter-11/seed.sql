-- Cinetrack chapter-11 seed.
-- ~50,000 movies, ~10,000 users, ~500,000 ratings, ~50,000 reviews,
-- ~200,000 view_events. Big enough that join order and join algorithm
-- produce visibly different runtimes; small enough to seed in a minute.
-- Re-runnable: TRUNCATE first, then insert.

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

-- ~10% of users are deleted, ~50% have logged in within 7 days.
INSERT INTO users (username, email, last_login_at, deleted_at)
SELECT
    format('user%s', g),
    format('user%s@cinetrack.test', g),
    CASE WHEN g % 2 = 0
        THEN now() - ((g % 7) || ' days')::interval
        ELSE now() - ((g % 60) || ' days')::interval
    END,
    CASE WHEN g % 10 = 0
        THEN now() - ((g % 30) || ' days')::interval
        ELSE NULL
    END
FROM generate_series(1, 10000) AS g;

-- 500k ratings spread across users and movies.
INSERT INTO ratings (user_id, movie_id, score, rated_at)
SELECT
    ((g - 1) % 10000) + 1,
    ((g * 17) % 50000) + 1,
    ((g * 7) % 10) + 1,
    now() - ((g % 9000) || ' minutes')::interval
FROM generate_series(1, 500000) AS g;

-- 50k reviews. Most movies have a handful, a few are popular and have many.
INSERT INTO reviews (user_id, movie_id, body, posted_at)
SELECT
    ((g - 1) % 10000) + 1,
    -- Bias movie_id toward a smaller range to make some movies "hot".
    CASE WHEN g % 5 = 0 THEN ((g * 3) % 1000) + 1
         ELSE ((g * 13) % 50000) + 1
    END,
    CASE (g % 5)
        WHEN 0 THEN 'A slow burn that rewards patience.'
        WHEN 1 THEN 'Too long by half, but the third act lands.'
        WHEN 2 THEN 'Stunning cinematography. Story is fine.'
        WHEN 3 THEN 'I expected to hate this. I did not.'
        WHEN 4 THEN 'Will not watch again. Will not forget.'
    END,
    now() - ((g % 30000) || ' minutes')::interval
FROM generate_series(1, 50000) AS g;

-- 200k view events. Distribution matters for the running-total demo:
-- some users have many events, most have a few.
INSERT INTO view_events (user_id, movie_id, occurred_at, session_length)
SELECT
    -- Power users at the low end of the user_id range.
    CASE WHEN g % 20 = 0 THEN ((g * 3) % 100) + 1
         ELSE ((g - 1) % 10000) + 1
    END,
    ((g * 19) % 50000) + 1,
    now() - ((g * 3) % 60000)::int * interval '1 minute',
    30 + (g * 11) % 180
FROM generate_series(1, 200000) AS g;

ANALYZE movies;
ANALYZE users;
ANALYZE ratings;
ANALYZE reviews;
ANALYZE view_events;

COMMIT;

SELECT 'movies'      AS tbl, count(*) FROM movies
UNION ALL SELECT 'users',       count(*) FROM users
UNION ALL SELECT 'ratings',     count(*) FROM ratings
UNION ALL SELECT 'reviews',     count(*) FROM reviews
UNION ALL SELECT 'view_events', count(*) FROM view_events;
