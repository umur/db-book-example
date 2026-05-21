-- Cinetrack chapter-20 seed.
-- 50,000 movies, 10,000 users, ~30,000 follow edges, 500,000 reviews.
-- The size matters: at this row count, the planner's home-feed choice
-- flips to the bad plan that section 20.8 walks through.

BEGIN;

TRUNCATE TABLE reviews, follows, users, movies RESTART IDENTITY CASCADE;

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
    1970 + (g % 55),
    85 + (g * 5) % 70,
    CASE (g % 6)
        WHEN 0 THEN 'A. Reiner'
        WHEN 1 THEN 'B. Coen'
        WHEN 2 THEN 'C. Nolan'
        WHEN 3 THEN 'D. Villeneuve'
        WHEN 4 THEN 'E. Park'
        WHEN 5 THEN 'F. Bigelow'
    END
FROM generate_series(1, 50000) AS g;

INSERT INTO users (username, email)
SELECT
    format('user%s', g),
    format('user%s@cinetrack.test', g)
FROM generate_series(1, 10000) AS g;

-- Follow edges: each user follows 3 others, deterministic offsets.
INSERT INTO follows (follower_id, followed_id)
SELECT DISTINCT ON (f, t) f, t
FROM (
    SELECT
        u                                      AS f,
        ((u + delta - 1) % 10000) + 1          AS t
    FROM generate_series(1, 10000) AS u
    CROSS JOIN unnest(ARRAY[7, 23, 71]) AS delta
) s(f, t)
WHERE f <> t;

-- 500,000 reviews. posted_at spreads over the last year so ORDER BY
-- DESC produces a meaningful sort, and so the bad plan's sort cost
-- is realistic.
INSERT INTO reviews (user_id, movie_id, body, posted_at)
SELECT
    ((g - 1) % 10000) + 1,
    ((g * 11) % 50000) + 1,
    CASE (g % 6)
        WHEN 0 THEN 'A slow burn that rewards patient viewers.'
        WHEN 1 THEN 'Stunning cinematography. The lighting is the star.'
        WHEN 2 THEN 'Too long by half, but the third act lands.'
        WHEN 3 THEN 'I expected to hate this. I did not.'
        WHEN 4 THEN 'Patient, careful, deliberate filmmaking.'
        WHEN 5 THEN 'Burns slow, hits hard, ends without warning.'
    END,
    now() - (random() * interval '365 days')
FROM generate_series(1, 500000) AS g;

ANALYZE movies;
ANALYZE users;
ANALYZE follows;
ANALYZE reviews;

COMMIT;

SELECT 'movies'  AS tbl, count(*) FROM movies
UNION ALL SELECT 'users',   count(*) FROM users
UNION ALL SELECT 'follows', count(*) FROM follows
UNION ALL SELECT 'reviews', count(*) FROM reviews;
