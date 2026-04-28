-- Cinetrack chapter-1 seed.
-- ~100 movies, ~50 users, ~500 ratings, ~50 reviews, plus a few watchlists,
-- view events, and notifications. Realistic enough for the MVCC peeks the
-- chapter asks for. Re-runnable: TRUNCATE first, then insert.

BEGIN;

TRUNCATE TABLE notifications, view_events, watchlists, reviews, ratings, users, movies
RESTART IDENTITY CASCADE;

-- 100 movies. A real-ish catalog. Generated rather than hand-typed.
INSERT INTO movies (title, release_year, runtime_min, director)
SELECT
    format('Cinetrack Test Movie %s', g),
    1970 + (g % 55),                                  -- spread releases across 55 years
    80 + (g * 7) % 100,                               -- runtimes 80..179
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

-- 50 users.
INSERT INTO users (username, email)
SELECT
    format('user%s', g),
    format('user%s@cinetrack.test', g)
FROM generate_series(1, 50) AS g;

-- ~500 ratings. Each user rates ~10 random movies, scores 1..10.
INSERT INTO ratings (user_id, movie_id, score)
SELECT DISTINCT ON (u, m) u, m, ((u * 7 + m * 3) % 10) + 1
FROM (
    SELECT
        ((g - 1) % 50) + 1                    AS u,
        ((g * 17) % 100) + 1                  AS m
    FROM generate_series(1, 600) AS g
) s(u, m);

-- ~50 reviews. Hand-written enough to read.
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

-- A few watchlists.
INSERT INTO watchlists (user_id, movie_id)
SELECT DISTINCT ON (u, m) u, m
FROM (
    SELECT
        ((g - 1) % 50) + 1                    AS u,
        ((g * 11) % 100) + 1                  AS m
    FROM generate_series(1, 200) AS g
) s(u, m);

-- A small batch of view events.
INSERT INTO view_events (user_id, movie_id, duration_sec, occurred_at)
SELECT
    ((g - 1) % 50) + 1,
    ((g * 19) % 100) + 1,
    600 + (g % 6000),
    now() - (g || ' minutes')::interval
FROM generate_series(1, 300) AS g;

-- A handful of pending notifications.
INSERT INTO notifications (user_id, payload)
SELECT
    ((g - 1) % 50) + 1,
    jsonb_build_object(
        'kind',   'review_reply',
        'review', g,
        'from',   format('user%s', ((g * 3) % 50) + 1)
    )
FROM generate_series(1, 20) AS g;

COMMIT;

-- Quick sanity counts.
SELECT 'movies'         AS tbl, count(*) FROM movies
UNION ALL SELECT 'users',          count(*) FROM users
UNION ALL SELECT 'ratings',        count(*) FROM ratings
UNION ALL SELECT 'reviews',        count(*) FROM reviews
UNION ALL SELECT 'watchlists',     count(*) FROM watchlists
UNION ALL SELECT 'view_events',    count(*) FROM view_events
UNION ALL SELECT 'notifications',  count(*) FROM notifications;
