-- Cinetrack chapter-6 seed.
-- 10,000 movies, 5,000 users, 2,000,000 ratings. Sized so that the ratings
-- table outgrows shared_buffers on the default Docker config, the
-- sequential scan vs index scan transition is visible (and not hidden by
-- the OS page cache), and the B-tree on movie_id has multiple internal
-- levels so bt_metap() and bt_page_stats() actually have something to say.
-- Also sized so the bloat demo in index-tour.sql produces an observable
-- size delta after a few thousand updates.

BEGIN;

TRUNCATE TABLE reviews, ratings, users, movies RESTART IDENTITY CASCADE;

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
FROM generate_series(1, 10000) AS g;

INSERT INTO users (username, email)
SELECT
    format('user%s', g),
    format('user%s@cinetrack.test', g)
FROM generate_series(1, 5000) AS g;

INSERT INTO ratings (user_id, movie_id, score)
SELECT
    ((g - 1) % 5000) + 1,
    ((g * 17) % 10000) + 1,
    ((g * 7) % 10) + 1
FROM generate_series(1, 2000000) AS g;

INSERT INTO reviews (user_id, movie_id, body)
SELECT
    ((g - 1) % 5000) + 1,
    ((g * 13) % 10000) + 1,
    CASE (g % 5)
        WHEN 0 THEN 'A slow burn that rewards patience.'
        WHEN 1 THEN 'Too long by half, but the third act lands.'
        WHEN 2 THEN 'Stunning cinematography. Story is fine.'
        WHEN 3 THEN 'I expected to hate this. I did not.'
        WHEN 4 THEN 'Will not watch again. Will not forget.'
    END
FROM generate_series(1, 5000) AS g;

COMMIT;

ANALYZE;

SELECT 'movies'   AS tbl, count(*) FROM movies
UNION ALL SELECT 'users',   count(*) FROM users
UNION ALL SELECT 'ratings', count(*) FROM ratings
UNION ALL SELECT 'reviews', count(*) FROM reviews;
