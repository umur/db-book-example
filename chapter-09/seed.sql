-- Cinetrack chapter-9 seed.
-- Bigger numbers than chapter-2: ~50,000 movies, ~10,000 users,
-- ~500,000 ratings, ~50,000 reviews, ~50,000 notifications.
-- Re-runnable: TRUNCATE first, then insert.

BEGIN;

TRUNCATE TABLE screen_bookings, notifications, watchlists, reviews, ratings,
               users, movies
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
    -- Mixed-case emails so the LOWER(email) expression index has work to do.
    CASE (g % 3)
        WHEN 0 THEN format('User%s@Cinetrack.test', g)
        WHEN 1 THEN format('user%s@cinetrack.test', g)
        WHEN 2 THEN format('USER%s@CINETRACK.TEST', g)
    END
FROM generate_series(1, 10000) AS g;

INSERT INTO ratings (user_id, movie_id, score)
SELECT DISTINCT ON (u, m) u, m, ((u * 7 + m * 3) % 10) + 1
FROM (
    SELECT
        ((g - 1) % 10000) + 1                 AS u,
        ((g * 17) % 50000) + 1                AS m
    FROM generate_series(1, 600000) AS g
) s(u, m);

INSERT INTO reviews (user_id, movie_id, body)
SELECT
    ((g - 1) % 10000) + 1,
    ((g * 13) % 50000) + 1,
    CASE (g % 5)
        WHEN 0 THEN 'A slow burn that rewards patience.'
        WHEN 1 THEN 'Too long by half, but the third act lands.'
        WHEN 2 THEN 'Stunning cinematography. Story is fine.'
        WHEN 3 THEN 'I expected to hate this. I did not.'
        WHEN 4 THEN 'Will not watch again. Will not forget.'
    END
FROM generate_series(1, 50000) AS g;

INSERT INTO watchlists (user_id, movie_id)
SELECT DISTINCT ON (u, m) u, m
FROM (
    SELECT
        ((g - 1) % 10000) + 1                 AS u,
        ((g * 11) % 50000) + 1                AS m
    FROM generate_series(1, 100000) AS g
) s(u, m);

-- Most notifications are 'sent', a few hundred are 'pending'.
-- This is the partial-index demo's core: a fat audit table with a tiny
-- live slice.
INSERT INTO notifications (user_id, payload, status, delivered_at)
SELECT
    ((g - 1) % 10000) + 1,
    jsonb_build_object(
        'kind',   'review_reply',
        'review', g,
        'from',   format('user%s', ((g * 3) % 10000) + 1)
    ),
    CASE
        WHEN g <= 200 THEN 'pending'
        WHEN g % 1000 = 0 THEN 'failed'
        ELSE 'sent'
    END,
    CASE
        WHEN g <= 200 THEN NULL
        WHEN g % 1000 = 0 THEN NULL
        ELSE now() - ((g % 10000) || ' minutes')::interval
    END
FROM generate_series(1, 50000) AS g;

-- Three non-overlapping bookings on screen 1 for the EXCLUDE constraint demo.
INSERT INTO screen_bookings (screen_id, booking) VALUES
    (1, tstzrange('2025-04-15 10:00+00', '2025-04-15 12:00+00', '[)')),
    (1, tstzrange('2025-04-15 14:00+00', '2025-04-15 16:00+00', '[)')),
    (1, tstzrange('2025-04-15 18:00+00', '2025-04-15 20:00+00', '[)'));

ANALYZE movies;
ANALYZE users;
ANALYZE ratings;
ANALYZE reviews;
ANALYZE watchlists;
ANALYZE notifications;
ANALYZE screen_bookings;

COMMIT;

SELECT 'movies'         AS tbl, count(*) FROM movies
UNION ALL SELECT 'users',          count(*) FROM users
UNION ALL SELECT 'ratings',        count(*) FROM ratings
UNION ALL SELECT 'reviews',        count(*) FROM reviews
UNION ALL SELECT 'watchlists',     count(*) FROM watchlists
UNION ALL SELECT 'notifications',  count(*) FROM notifications
UNION ALL SELECT 'screen_bookings',count(*) FROM screen_bookings;
