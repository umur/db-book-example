-- Cinetrack chapter-18 seed.
-- Larger than the earlier chapters: 100 movies, 1,000 users, 50,000 reviews.
-- Big enough to make autovacuum behavior interesting on a laptop.
-- Re-runnable: TRUNCATE first, then insert.

BEGIN;

TRUNCATE TABLE reviews, users, movies RESTART IDENTITY CASCADE;

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
FROM generate_series(1, 1000) AS g;

INSERT INTO reviews (user_id, movie_id, body)
SELECT
    ((g - 1) % 1000) + 1,
    ((g * 13) % 100) + 1,
    CASE (g % 6)
        WHEN 0 THEN 'A slow burn that rewards patience.'
        WHEN 1 THEN 'Too long by half, but the third act lands.'
        WHEN 2 THEN 'Stunning cinematography. Story is fine.'
        WHEN 3 THEN 'I expected to hate this. I did not.'
        WHEN 4 THEN 'Will not watch again. Will not forget.'
        WHEN 5 THEN 'A masterclass in restraint and timing.'
    END
FROM generate_series(1, 50000) AS g;

COMMIT;

ANALYZE movies;
ANALYZE users;
ANALYZE reviews;

SELECT 'movies'  AS tbl, count(*) FROM movies
UNION ALL SELECT 'users',   count(*) FROM users
UNION ALL SELECT 'reviews', count(*) FROM reviews;
