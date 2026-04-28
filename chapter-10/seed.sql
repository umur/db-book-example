-- Cinetrack chapter-10 seed.
-- Sized for the specialty index tour. The view_events table is large
-- (~10M rows via generate_series) so BRIN vs B-tree size differences are
-- visible in pg_relation_size. The other tables stay laptop-friendly.

BEGIN;

TRUNCATE TABLE sessions, screen_bookings, event_attributes, view_events,
               notifications, reviews, users, movies
RESTART IDENTITY CASCADE;

-- 50,000 movies, with multi-valued genres and JSONB metadata so the GIN
-- demos have something to chew on.
INSERT INTO movies (title, release_year, runtime_min, director, genres, metadata)
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
    END,
    CASE (g % 5)
        WHEN 0 THEN ARRAY['drama', 'thriller']
        WHEN 1 THEN ARRAY['comedy']
        WHEN 2 THEN ARRAY['drama', 'romance']
        WHEN 3 THEN ARRAY['action', 'sci-fi']
        WHEN 4 THEN ARRAY['documentary']
    END,
    jsonb_build_object(
        'language', CASE (g % 4)
                        WHEN 0 THEN 'en'
                        WHEN 1 THEN 'fr'
                        WHEN 2 THEN 'ja'
                        WHEN 3 THEN 'es'
                    END,
        'awards',   CASE WHEN g % 100 = 0 THEN jsonb_build_array('palme-dor')
                         WHEN g % 200 = 0 THEN jsonb_build_array('oscar')
                         ELSE '[]'::jsonb
                    END,
        'rating',   ((g % 9) + 1)
    )
FROM generate_series(1, 50000) AS g;

INSERT INTO users (username, email)
SELECT
    format('user%s', g),
    format('user%s@cinetrack.test', g)
FROM generate_series(1, 10000) AS g;

INSERT INTO reviews (user_id, movie_id, body)
SELECT
    ((g - 1) % 10000) + 1,
    ((g * 13) % 50000) + 1,
    CASE (g % 5)
        WHEN 0 THEN 'A slow burn that rewards patience. The cinematography is stunning.'
        WHEN 1 THEN 'Too long by half, but the third act lands. Worth the wait.'
        WHEN 2 THEN 'Stunning cinematography. Story is fine. The lead performance carries it.'
        WHEN 3 THEN 'I expected to hate this. I did not. The score, especially.'
        WHEN 4 THEN 'Will not watch again. Will not forget. Inception-level twist.'
    END
FROM generate_series(1, 50000) AS g;

INSERT INTO notifications (user_id, payload, status)
SELECT
    ((g - 1) % 10000) + 1,
    jsonb_build_object(
        'kind',   CASE (g % 4)
                      WHEN 0 THEN 'review_reply'
                      WHEN 1 THEN 'rating_milestone'
                      WHEN 2 THEN 'mention'
                      WHEN 3 THEN 'follow'
                  END,
        'review', g,
        'from',   format('user%s', ((g * 3) % 10000) + 1)
    ),
    CASE WHEN g <= 200 THEN 'pending' ELSE 'sent' END
FROM generate_series(1, 50000) AS g;

-- 10M view_events. Append-only insertion order keeps event_at correlated
-- with heap order, which is what BRIN needs to win. Events are spread
-- evenly across all of 2024 (~3.15 seconds between rows) so range queries
-- against any day of the year return non-empty result sets.
INSERT INTO view_events (user_id, movie_id, event_at)
SELECT
    ((g - 1) % 10000) + 1,
    ((g * 17) % 50000) + 1,
    timestamptz '2024-01-01 00:00+00'
        + (((g - 1) * 3.1536) || ' seconds')::interval
FROM generate_series(1, 10000000) AS g;

-- Wide low-cardinality table for the bloom demo.
INSERT INTO event_attributes (event_id, region, device_class, plan, referrer, browser, os)
SELECT
    g,
    CASE (g % 4) WHEN 0 THEN 'EU' WHEN 1 THEN 'US' WHEN 2 THEN 'APAC' WHEN 3 THEN 'LATAM' END,
    CASE (g % 3) WHEN 0 THEN 'mobile' WHEN 1 THEN 'desktop' WHEN 2 THEN 'tablet' END,
    CASE (g % 3) WHEN 0 THEN 'free' WHEN 1 THEN 'pro' WHEN 2 THEN 'enterprise' END,
    CASE (g % 5) WHEN 0 THEN 'google' WHEN 1 THEN 'twitter' WHEN 2 THEN 'reddit'
                 WHEN 3 THEN 'direct' WHEN 4 THEN 'email' END,
    CASE (g % 4) WHEN 0 THEN 'chrome' WHEN 1 THEN 'safari' WHEN 2 THEN 'firefox' WHEN 3 THEN 'edge' END,
    CASE (g % 3) WHEN 0 THEN 'macos' WHEN 1 THEN 'windows' WHEN 2 THEN 'linux' END
FROM generate_series(1, 500000) AS g;

-- Three non-overlapping bookings on screen 1 for the EXCLUDE demo.
INSERT INTO screen_bookings (screen_id, booking) VALUES
    (1, tstzrange('2025-04-15 10:00+00', '2025-04-15 12:00+00', '[)')),
    (1, tstzrange('2025-04-15 14:00+00', '2025-04-15 16:00+00', '[)')),
    (1, tstzrange('2025-04-15 18:00+00', '2025-04-15 20:00+00', '[)'));

-- Sessions for the Hash demo. Long opaque tokens make the size argument
-- visible: a B-tree on token stores the full string in every leaf entry.
INSERT INTO sessions (user_id, token, expires_at)
SELECT
    ((g - 1) % 10000) + 1,
    encode(sha256(random()::text::bytea), 'hex') ||
        encode(sha256((random()+1)::text::bytea), 'hex'),
    now() + interval '7 days'
FROM generate_series(1, 100000) AS g;

ANALYZE movies;
ANALYZE users;
ANALYZE reviews;
ANALYZE notifications;
ANALYZE view_events;
ANALYZE event_attributes;
ANALYZE screen_bookings;
ANALYZE sessions;

COMMIT;

SELECT 'movies'           AS tbl, count(*) FROM movies
UNION ALL SELECT 'users',           count(*) FROM users
UNION ALL SELECT 'reviews',         count(*) FROM reviews
UNION ALL SELECT 'notifications',   count(*) FROM notifications
UNION ALL SELECT 'view_events',     count(*) FROM view_events
UNION ALL SELECT 'event_attributes',count(*) FROM event_attributes
UNION ALL SELECT 'screen_bookings', count(*) FROM screen_bookings
UNION ALL SELECT 'sessions',        count(*) FROM sessions;
