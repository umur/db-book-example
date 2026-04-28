-- Chapter 14 schema and partitioning tour.
-- Run top to bottom against a freshly seeded cinetrack-ch14 database.
-- Each numbered section maps to a moment in the chapter prose.

-- (1) The partitioned table, listed.
--     One parent (view_events), thirteen monthly children, plus the
--     default catch-all partition. Sizes give a sense of distribution.
SELECT
    inhrelid::regclass AS partition,
    pg_size_pretty(pg_relation_size(inhrelid)) AS size,
    pg_get_expr(c.relpartbound, inhrelid) AS bounds
FROM pg_inherits
JOIN pg_class c ON c.oid = pg_inherits.inhrelid
WHERE inhparent = 'view_events'::regclass
ORDER BY inhrelid::regclass::text;

-- (2) Partition pruning fires: a one-month range filter on the partition key.
--     Expected plan: Append over a single child (the matching month).
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*)
FROM view_events
WHERE occurred_at >= date_trunc('month', now())
  AND occurred_at <  date_trunc('month', now()) + interval '1 month';

-- (3) Partition pruning fires at execution time: a parameterised range.
--     Expected plan: Append with most subplans 'Subplans Removed: N'.
PREPARE recent (interval) AS
SELECT count(*)
FROM view_events
WHERE occurred_at >= now() - $1
  AND occurred_at <  now();

EXPLAIN (ANALYZE, BUFFERS) EXECUTE recent (interval '7 days');

DEALLOCATE recent;

-- (4) Pruning DOES NOT fire: filter wraps the partition key in date_trunc.
--     Logically equivalent to a one-month filter, but the planner cannot
--     prove it. Expected plan: Append over EVERY child partition.
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*)
FROM view_events
WHERE date_trunc('month', occurred_at) = date_trunc('month', now());

-- (5) The same query, written the right way. Expected plan: one child.
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*)
FROM view_events
WHERE occurred_at >= date_trunc('month', now())
  AND occurred_at <  date_trunc('month', now()) + interval '1 month';

-- (6) Comparison against the unpartitioned legacy table.
--     idx_view_events_legacy_occurred handles this on a 1M-row sandbox,
--     but on a 100M-row real table the partitioned version's per-partition
--     index depth and concentrated cache hits start to dominate.
EXPLAIN (ANALYZE, BUFFERS)
SELECT user_id, count(*) AS plays
FROM view_events_legacy
WHERE occurred_at >= now() - interval '30 days'
GROUP BY user_id
ORDER BY plays DESC
LIMIT 10;

EXPLAIN (ANALYZE, BUFFERS)
SELECT user_id, count(*) AS plays
FROM view_events
WHERE occurred_at >= now() - interval '30 days'
GROUP BY user_id
ORDER BY plays DESC
LIMIT 10;

-- (7) ATTACH PARTITION: build a partition standalone, populate it, attach.
--     This is the chapter-21 zero-downtime pattern in miniature. Here we
--     create a future-month partition for the upcoming month so live
--     inserts into next month's range route correctly.
DO $$
DECLARE
    next_month DATE := date_trunc('month', now() + interval '1 month');
    part_name  TEXT := format('view_events_%s', to_char(next_month, 'YYYY_MM'));
BEGIN
    EXECUTE format(
        'CREATE TABLE IF NOT EXISTS %I (LIKE view_events INCLUDING ALL)',
        part_name
    );
    EXECUTE format(
        'ALTER TABLE view_events ATTACH PARTITION %I
         FOR VALUES FROM (%L) TO (%L)',
        part_name,
        next_month,
        next_month + interval '1 month'
    );
END$$;

-- Verify: the new partition appears in the inheritance listing.
SELECT inhrelid::regclass AS partition,
       pg_get_expr(c.relpartbound, inhrelid) AS bounds
FROM pg_inherits
JOIN pg_class c ON c.oid = pg_inherits.inhrelid
WHERE inhparent = 'view_events'::regclass
ORDER BY inhrelid::regclass::text;

-- (8) Migrating from the legacy single table to partitions, one month at
--     a time. In production this runs as small transactions during a
--     dual-write window (full version in chapter 21). Here we just show
--     the per-month INSERT shape that the migration would issue.
EXPLAIN (ANALYZE, BUFFERS)
INSERT INTO view_events (user_id, movie_id, seconds, completed, occurred_at)
SELECT user_id, movie_id, seconds, completed, occurred_at
FROM view_events_legacy
WHERE occurred_at >= date_trunc('month', now()) - interval '1 month'
  AND occurred_at <  date_trunc('month', now());

-- (9) Generated columns demo: the reviews table has body_length and
--     search_tsv as STORED generated columns. body_length is cheap;
--     search_tsv is the canonical pattern from chapter 13.
SELECT id, body_length,
       length(body)             AS recomputed_length,
       search_tsv
FROM reviews
WHERE id <= 3
ORDER BY id;

-- The expression cannot be written: generated columns are read-only.
-- Uncomment to see the error PostgreSQL raises.
-- UPDATE reviews SET body_length = 0 WHERE id = 1;

-- (10) Constraint demo: EXCLUDE prevents overlapping screen bookings.
--      The first INSERT succeeds; the second raises a constraint violation
--      because its time range overlaps with an existing booking on the
--      same screen.
INSERT INTO screen_bookings (screen_id, booking)
VALUES (99, tstzrange(now() + interval '1 day',
                      now() + interval '1 day' + interval '2 hours',
                      '[)'));

-- Expected: ERROR  conflicting key value violates exclusion constraint
INSERT INTO screen_bookings (screen_id, booking)
VALUES (99, tstzrange(now() + interval '1 day' + interval '1 hour',
                      now() + interval '1 day' + interval '3 hours',
                      '[)'));

-- (11) Dropping a partition: O(milliseconds) retention.
--      DETACH first (so reads in flight don't crash), then DROP. On a
--      production-sized partition this is the difference between an
--      instant DROP and a multi-hour DELETE plus vacuum.
DO $$
DECLARE
    oldest_month DATE := date_trunc('month', now()) - interval '12 months';
    part_name    TEXT := format('view_events_%s', to_char(oldest_month, 'YYYY_MM'));
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_class
        WHERE relname = part_name
    ) THEN
        EXECUTE format('ALTER TABLE view_events DETACH PARTITION %I', part_name);
        EXECUTE format('DROP TABLE %I', part_name);
    END IF;
END$$;

-- (12) Sanity check: per-partition row counts. Distribution should be roughly
--      even across the months the seed populated, with the freshly-dropped
--      month gone from the listing.
SELECT
    inhrelid::regclass AS partition,
    pg_size_pretty(pg_relation_size(inhrelid)) AS size,
    (SELECT count(*) FROM view_events
       WHERE tableoid = inhrelid) AS approximate_rows
FROM pg_inherits
WHERE inhparent = 'view_events'::regclass
ORDER BY inhrelid::regclass::text;
