-- Cinetrack chapter-13 seed.
-- Search-friendly volumes: ~50,000 movies, ~10,000 users, ~100,000 reviews.
-- Review bodies are sampled from a pool of phrases with overlapping vocabulary
-- so the FTS demos return non-trivial result sets.
-- Re-runnable: TRUNCATE first, then insert.

BEGIN;

TRUNCATE TABLE watchlists, reviews, ratings, users, movies
RESTART IDENTITY CASCADE;

-- Movies: 50,000 rows. Titles seeded from a small vocabulary so searches
-- like 'patient', 'samurai', 'noir' have multiple hits to rank against.
INSERT INTO movies (title, release_year, runtime_min, director)
SELECT
    CASE (g % 12)
        WHEN 0  THEN format('The Patient Hour %s',    g)
        WHEN 1  THEN format('Seven Samurai Reloaded %s', g)
        WHEN 2  THEN format('Slow Burn %s',           g)
        WHEN 3  THEN format('Noir City %s',           g)
        WHEN 4  THEN format('The Long Night %s',      g)
        WHEN 5  THEN format('A Quiet Cinematography %s', g)
        WHEN 6  THEN format('Last Train Home %s',     g)
        WHEN 7  THEN format('The Editor''s Cut %s',   g)
        WHEN 8  THEN format('Dust and Light %s',      g)
        WHEN 9  THEN format('The Director''s Hand %s', g)
        WHEN 10 THEN format('Storm Over the Bay %s',  g)
        WHEN 11 THEN format('A Patient Viewer %s',    g)
    END,
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
    format('user%s@cinetrack.test', g)
FROM generate_series(1, 10000) AS g;

INSERT INTO ratings (user_id, movie_id, score)
SELECT DISTINCT ON (u, m) u, m, ((u * 7 + m * 3) % 10) + 1
FROM (
    SELECT
        ((g - 1) % 10000) + 1                 AS u,
        ((g * 17) % 50000) + 1                AS m
    FROM generate_series(1, 600000) AS g
) s(u, m);

-- Reviews: 100,000 rows. Bodies sampled from a pool that overlaps with
-- the title vocabulary so combined searches produce realistic ranks.
INSERT INTO reviews (user_id, movie_id, body)
SELECT
    ((g - 1) % 10000) + 1,
    ((g * 13) % 50000) + 1,
    CASE (g % 10)
        WHEN 0 THEN 'A slow burn that rewards patient viewers who keep watching.'
        WHEN 1 THEN 'Stunning cinematography. The story is fine, the lighting is the star.'
        WHEN 2 THEN 'Too long by half, but the third act lands like a punch.'
        WHEN 3 THEN 'I expected to hate this. I did not. The director sneaks up on you.'
        WHEN 4 THEN 'Will not watch again. Will not forget. The samurai sequence is unreal.'
        WHEN 5 THEN 'Patient, careful, deliberate filmmaking. Not for everyone.'
        WHEN 6 THEN 'Noir-flavored with a modern twist. The editing is the giveaway.'
        WHEN 7 THEN 'The third reel cinematography is some of the best of the decade.'
        WHEN 8 THEN 'A quiet meditation on memory and dust. Bring a long attention span.'
        WHEN 9 THEN 'Burns slow, hits hard, ends without warning. The viewer is the subject.'
    END
FROM generate_series(1, 100000) AS g;

INSERT INTO watchlists (user_id, movie_id)
SELECT DISTINCT ON (u, m) u, m
FROM (
    SELECT
        ((g - 1) % 10000) + 1                 AS u,
        ((g * 11) % 50000) + 1                AS m
    FROM generate_series(1, 100000) AS g
) s(u, m);

ANALYZE movies;
ANALYZE users;
ANALYZE ratings;
ANALYZE reviews;
ANALYZE watchlists;

COMMIT;

SELECT 'movies'      AS tbl, count(*) FROM movies
UNION ALL SELECT 'users',       count(*) FROM users
UNION ALL SELECT 'ratings',     count(*) FROM ratings
UNION ALL SELECT 'reviews',     count(*) FROM reviews
UNION ALL SELECT 'watchlists',  count(*) FROM watchlists;
