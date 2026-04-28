-- Cinetrack chapter-12 seed.
-- 50,000 movies with realistic JSONB metadata: languages, alternate titles,
-- awards, production info, tags, and format. Re-runnable: TRUNCATE first.

BEGIN;

TRUNCATE TABLE movies RESTART IDENTITY CASCADE;

INSERT INTO movies (title, director, release_year, runtime_min, rating_avg, metadata)
SELECT
    format('Cinetrack Test Movie %s', g),
    CASE (g % 8)
        WHEN 0 THEN 'A. Reiner'
        WHEN 1 THEN 'B. Coen'
        WHEN 2 THEN 'C. Nolan'
        WHEN 3 THEN 'D. Villeneuve'
        WHEN 4 THEN 'E. Park'
        WHEN 5 THEN 'F. Bigelow'
        WHEN 6 THEN 'G. Kurosawa'
        WHEN 7 THEN 'H. Lee'
    END,
    1970 + (g % 55),
    80 + (g * 7) % 100,
    round(((g * 13) % 100) / 10.0 + 1.0, 1)::numeric(3,1),
    jsonb_build_object(
        'languages',
            CASE (g % 4)
                WHEN 0 THEN jsonb_build_array('en')
                WHEN 1 THEN jsonb_build_array('en', 'fr')
                WHEN 2 THEN jsonb_build_array('en', 'es', 'pt')
                WHEN 3 THEN jsonb_build_array('ja', 'en')
            END,
        'alternate_titles',
            jsonb_build_array(
                jsonb_build_object(
                    'region', 'FR',
                    'title',  format('Origine %s', g)
                ),
                jsonb_build_object(
                    'region', 'JP',
                    'title',  format('Cinetrack %s', g)
                )
            ),
        'awards',
            CASE WHEN g % 7 = 0 THEN
                jsonb_build_array(
                    jsonb_build_object(
                        'name',     'Oscar',
                        'year',     2000 + (g % 25),
                        'category', CASE (g % 3)
                                        WHEN 0 THEN 'Cinematography'
                                        WHEN 1 THEN 'Sound'
                                        WHEN 2 THEN 'Editing'
                                    END
                    ),
                    jsonb_build_object(
                        'name',     'BAFTA',
                        'year',     2000 + (g % 25),
                        'category', 'Sound'
                    )
                )
            ELSE
                '[]'::jsonb
            END,
        'production',
            jsonb_build_object(
                'country', CASE (g % 5)
                              WHEN 0 THEN 'US'
                              WHEN 1 THEN 'UK'
                              WHEN 2 THEN 'FR'
                              WHEN 3 THEN 'JP'
                              WHEN 4 THEN 'KR'
                          END,
                'studios', jsonb_build_array(
                    format('Studio %s', g % 50),
                    format('Studio %s', (g * 3) % 50)
                )
            ),
        'tags',
            CASE (g % 6)
                WHEN 0 THEN jsonb_build_array('sci-fi', 'thriller')
                WHEN 1 THEN jsonb_build_array('drama')
                WHEN 2 THEN jsonb_build_array('comedy', 'romance')
                WHEN 3 THEN jsonb_build_array('documentary')
                WHEN 4 THEN jsonb_build_array('horror', 'thriller')
                WHEN 5 THEN jsonb_build_array('action', 'adventure')
            END,
        'format',
            jsonb_build_object(
                'color',        CASE WHEN g % 11 = 0 THEN 'b&w' ELSE 'color' END,
                'aspect_ratio', CASE (g % 3)
                                    WHEN 0 THEN '2.39:1'
                                    WHEN 1 THEN '1.85:1'
                                    WHEN 2 THEN '1.33:1'
                                END
            )
    )
FROM generate_series(1, 50000) AS g;

ANALYZE movies;

COMMIT;

SELECT 'movies' AS tbl, count(*) FROM movies;

-- A peek at one row's metadata so you can see the shape the tour is querying.
SELECT id, title, jsonb_pretty(metadata)
FROM movies WHERE id = 1;
