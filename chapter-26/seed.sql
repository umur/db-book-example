-- Seed the cinetrack tables. Three movies, three users, and 800
-- reviews scattered across them. The walkthrough's destructive DELETE
-- removes all 800; the PITR target recovers them.

INSERT INTO movies (title, released) VALUES
    ('Backup',          '2018-04-12'),
    ('Restore',         '2021-09-30'),
    ('Recovery Point',  '2025-02-14')
ON CONFLICT DO NOTHING;

INSERT INTO users (handle) VALUES
    ('umur'),
    ('alice'),
    ('bob')
ON CONFLICT DO NOTHING;

-- 800 reviews, distributed across users and movies. Generated with
-- generate_series so the row count is predictable for the walkthrough.
--
-- The WHERE NOT EXISTS guard skips the insert when `reviews` is
-- already populated, so a container restart that re-runs the seed
-- does not double the row count. This makes the seed non-idempotent
-- against an empty-but-previously-populated table: after the
-- destructive DELETE in the walkthrough the guard sees no rows and
-- would re-seed, defeating the recovery exercise. Always reset the
-- sandbox with `docker compose down -v` before re-seeding, not on top
-- of a partially-populated cluster.
INSERT INTO reviews (user_id, movie_id, body)
SELECT
    1 + (g % 3),
    1 + ((g / 3) % 3),
    'Review #' || g || ' generated for the chapter-26 walkthrough.'
FROM generate_series(1, 800) AS g
WHERE NOT EXISTS (SELECT 1 FROM reviews LIMIT 1);

INSERT INTO audit_log (note) VALUES
    ('Seed complete. 800 reviews loaded.');
