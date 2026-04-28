-- Cinetrack chapter-17 seed.
-- Modest volumes by design: this sandbox is for two-session SKIP LOCKED
-- demos and outbox publisher walkthroughs, not for benchmarking.
-- 5,000 movies, 1,000 users, ~3,000 follow edges, 5,000 reviews.
-- The notifications and outbox tables start empty; the queue-tour
-- script populates them through the application-style fanout query.
-- Re-runnable: TRUNCATE first, then insert.

BEGIN;

TRUNCATE TABLE notifications, outbox, reviews, follows, users, movies
RESTART IDENTITY CASCADE;

INSERT INTO movies (title, release_year, runtime_min, director)
SELECT
    CASE (g % 8)
        WHEN 0 THEN format('Slow Burn %s',           g)
        WHEN 1 THEN format('Noir City %s',           g)
        WHEN 2 THEN format('The Long Night %s',      g)
        WHEN 3 THEN format('A Quiet Cinema %s',      g)
        WHEN 4 THEN format('Last Train Home %s',     g)
        WHEN 5 THEN format('The Editor''s Cut %s',   g)
        WHEN 6 THEN format('Dust and Light %s',      g)
        WHEN 7 THEN format('Storm Over the Bay %s',  g)
    END,
    1980 + (g % 45),
    85 + (g * 5) % 70,
    CASE (g % 6)
        WHEN 0 THEN 'A. Reiner'
        WHEN 1 THEN 'B. Coen'
        WHEN 2 THEN 'C. Nolan'
        WHEN 3 THEN 'D. Villeneuve'
        WHEN 4 THEN 'E. Park'
        WHEN 5 THEN 'F. Bigelow'
    END
FROM generate_series(1, 5000) AS g;

INSERT INTO users (username, email)
SELECT
    format('user%s', g),
    format('user%s@cinetrack.test', g)
FROM generate_series(1, 1000) AS g;

-- Follow edges: each user follows roughly 3 others, deterministic offsets.
INSERT INTO follows (follower_id, followed_id)
SELECT DISTINCT ON (f, t) f, t
FROM (
    SELECT
        u                                    AS f,
        ((u + delta - 1) % 1000) + 1         AS t
    FROM generate_series(1, 1000) AS u
    CROSS JOIN unnest(ARRAY[7, 23, 71]) AS delta
) s(f, t)
WHERE f <> t;

-- 5,000 reviews. The queue-tour will use these directly and also create
-- new ones to demonstrate the fanout-in-a-transaction pattern.
INSERT INTO reviews (user_id, movie_id, body)
SELECT
    ((g - 1) % 1000) + 1,
    ((g * 11) % 5000) + 1,
    CASE (g % 6)
        WHEN 0 THEN 'A slow burn that rewards patient viewers.'
        WHEN 1 THEN 'Stunning cinematography. The lighting is the star.'
        WHEN 2 THEN 'Too long by half, but the third act lands.'
        WHEN 3 THEN 'I expected to hate this. I did not.'
        WHEN 4 THEN 'Patient, careful, deliberate filmmaking.'
        WHEN 5 THEN 'Burns slow, hits hard, ends without warning.'
    END
FROM generate_series(1, 5000) AS g;

ANALYZE movies;
ANALYZE users;
ANALYZE follows;
ANALYZE reviews;

COMMIT;

SELECT 'movies'        AS tbl, count(*) FROM movies
UNION ALL SELECT 'users',         count(*) FROM users
UNION ALL SELECT 'follows',       count(*) FROM follows
UNION ALL SELECT 'reviews',       count(*) FROM reviews
UNION ALL SELECT 'notifications', count(*) FROM notifications
UNION ALL SELECT 'outbox',        count(*) FROM outbox;
