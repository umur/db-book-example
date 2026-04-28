-- Chapter 28 sandbox seed. Small for the runbooks that just need a
-- working schema; large enough that the slow.md and
-- vacuum-falling-behind.md runbooks have realistic numbers to work
-- with.

INSERT INTO movies (title, released) VALUES
    ('The Disk Is Full',          '2018-03-12'),
    ('Replication Broke',         '2020-07-04'),
    ('Vacuum Cannot Keep Up',     '2022-10-31'),
    ('The Database Will Not Start','2023-05-19'),
    ('Postgres Is Slow',          '2024-09-08')
ON CONFLICT DO NOTHING;

INSERT INTO users (handle)
SELECT 'user_' || g
FROM generate_series(1, 200) g
ON CONFLICT DO NOTHING;

-- 50,000 reviews with a uniform spread across users and movies. Big
-- enough for the slow-query runbook to show off bad plans, small
-- enough to fit in the sandbox.
INSERT INTO reviews (user_id, movie_id, body, rating, posted_at)
SELECT
    1 + (g % 200),
    1 + (g % 5),
    'Review body number ' || g,
    1 + (g % 5),
    now() - (g || ' minutes')::interval
FROM generate_series(1, 50000) g;

-- 200,000 view events. The slow.md runbook adds a query that scans
-- this table without a proper index; the recovery is to add the index.
INSERT INTO view_events (user_id, movie_id, viewed_at)
SELECT
    1 + (g % 200),
    1 + (g % 5),
    now() - (g || ' seconds')::interval
FROM generate_series(1, 200000) g;

ANALYZE;
