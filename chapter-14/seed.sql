-- Cinetrack chapter-14 seed.
-- Volumes calibrated for partitioning demos:
--   movies     :     5,000 rows
--   users      :    10,000 rows
--   ratings    :    50,000 rows
--   reviews    :    20,000 rows
--   view_events: 1,000,000 rows spread across 13 months
--
-- The same view_events distribution is loaded into BOTH view_events_legacy
-- and view_events (the partitioned table) so EXPLAIN comparisons are honest.
-- Re-runnable: TRUNCATE first, then insert.

BEGIN;

TRUNCATE TABLE view_events_legacy, screen_bookings, reviews, ratings,
               watchlists, users, movies
RESTART IDENTITY CASCADE;

-- view_events: TRUNCATE the parent; CASCADE clears every partition.
TRUNCATE TABLE view_events RESTART IDENTITY CASCADE;

INSERT INTO movies (title, release_year, runtime_min, director)
SELECT
    CASE (g % 10)
        WHEN 0 THEN format('The Patient Hour %s',     g)
        WHEN 1 THEN format('Seven Samurai Reloaded %s', g)
        WHEN 2 THEN format('Slow Burn %s',            g)
        WHEN 3 THEN format('Noir City %s',            g)
        WHEN 4 THEN format('The Long Night %s',       g)
        WHEN 5 THEN format('A Quiet Cinematography %s', g)
        WHEN 6 THEN format('Last Train Home %s',      g)
        WHEN 7 THEN format('The Editor''s Cut %s',    g)
        WHEN 8 THEN format('Dust and Light %s',       g)
        WHEN 9 THEN format('A Patient Viewer %s',     g)
    END,
    1970 + (g % 55)::SMALLINT,
    (80 + (g * 7) % 100)::SMALLINT,
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
FROM generate_series(1, 5000) AS g;

INSERT INTO users (username, email)
SELECT
    format('user%s', g),
    format('user%s@cinetrack.test', g)
FROM generate_series(1, 10000) AS g;

INSERT INTO ratings (user_id, movie_id, score)
SELECT DISTINCT ON (u, m) u, m, ((u * 7 + m * 3) % 10 + 1)::SMALLINT
FROM (
    SELECT
        ((g - 1) % 10000) + 1 AS u,
        ((g * 17) %  5000) + 1 AS m
    FROM generate_series(1, 60000) AS g
) s(u, m);

INSERT INTO reviews (user_id, movie_id, body)
SELECT
    ((g - 1) % 10000) + 1,
    ((g * 13) %  5000) + 1,
    CASE (g % 8)
        WHEN 0 THEN 'A slow burn that rewards patient viewers who keep watching.'
        WHEN 1 THEN 'Stunning cinematography. The story is fine, the lighting is the star.'
        WHEN 2 THEN 'Too long by half, but the third act lands like a punch.'
        WHEN 3 THEN 'I expected to hate this. I did not. The director sneaks up on you.'
        WHEN 4 THEN 'Will not watch again. Will not forget.'
        WHEN 5 THEN 'Patient, careful, deliberate filmmaking. Not for everyone.'
        WHEN 6 THEN 'Noir-flavored with a modern twist. The editing is the giveaway.'
        WHEN 7 THEN 'A quiet meditation on memory and dust.'
    END
FROM generate_series(1, 20000) AS g;

-- view_events_legacy: 1M rows distributed across the same 13-month span
-- as the partitioned view_events. occurred_at picks a uniformly random
-- second within the [today - 13 months, today] interval.
INSERT INTO view_events_legacy (user_id, movie_id, seconds, completed, occurred_at)
SELECT
    ((g - 1) % 10000) + 1,
    ((g * 19) %  5000) + 1,
    ((g * 31) %  7200) + 1,
    (g % 5 = 0),
    now()
        - (interval '13 months')
        + (random() * interval '13 months')
FROM generate_series(1, 1000000) AS g;

-- view_events (partitioned): same shape, same distribution. Loading into
-- the parent automatically routes each row to the matching partition.
INSERT INTO view_events (user_id, movie_id, seconds, completed, occurred_at)
SELECT user_id, movie_id, seconds, completed, occurred_at
FROM view_events_legacy;

-- A small watchlist seed: the first 100 users each save five movies.
-- Enough rows to make the table honest, small enough to stay out of the way.
INSERT INTO watchlists (user_id, movie_id)
SELECT DISTINCT u, m
FROM (
    SELECT
        ((g - 1) % 100) + 1                  AS u,
        ((g * 23) %  5000) + 1               AS m
    FROM generate_series(1, 500) AS g
) s(u, m);

-- A handful of overlap-free screen bookings for the EXCLUDE demo.
INSERT INTO screen_bookings (screen_id, booking)
SELECT
    ((g - 1) % 5) + 1,
    tstzrange(
        now() + (g * interval '4 hours'),
        now() + (g * interval '4 hours') + interval '2 hours',
        '[)'
    )
FROM generate_series(1, 20) AS g;

ANALYZE movies;
ANALYZE users;
ANALYZE ratings;
ANALYZE reviews;
ANALYZE watchlists;
ANALYZE view_events_legacy;
ANALYZE view_events;
ANALYZE screen_bookings;

COMMIT;

SELECT 'movies'             AS tbl, count(*) FROM movies
UNION ALL SELECT 'users',         count(*) FROM users
UNION ALL SELECT 'ratings',       count(*) FROM ratings
UNION ALL SELECT 'reviews',       count(*) FROM reviews
UNION ALL SELECT 'watchlists',    count(*) FROM watchlists
UNION ALL SELECT 'view_events_legacy', count(*) FROM view_events_legacy
UNION ALL SELECT 'view_events (parent)', count(*) FROM view_events
UNION ALL SELECT 'screen_bookings', count(*) FROM screen_bookings
ORDER BY tbl;
