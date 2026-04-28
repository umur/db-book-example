-- Chapter 10 specialty index tour.
-- Run top to bottom against a freshly seeded cinetrack chapter-10 database.
-- Each numbered section maps to a moment in the chapter prose.

-- (1) Baseline: GIN on movies.genres for "contains" queries on an array.
--     Without the index, the query is a sequential scan. With it, the
--     planner uses a bitmap index scan over the inverted index.
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM movies WHERE genres @> ARRAY['drama'];
-- Seq Scan, no GIN yet.

CREATE INDEX idx_movies_genres_gin ON movies USING GIN (genres);

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM movies WHERE genres @> ARRAY['drama'];
-- Bitmap Index Scan + Bitmap Heap Scan.

-- (2) GIN on JSONB with jsonb_path_ops.
--     The jsonb_path_ops operator class only supports @>, but it's smaller
--     and faster than the default GIN class for that operator.
CREATE INDEX idx_notifications_payload_gin
    ON notifications USING GIN (payload jsonb_path_ops);

EXPLAIN (ANALYZE, BUFFERS)
SELECT id FROM notifications WHERE payload @> '{"kind": "review_reply"}';

-- (3) GiST EXCLUDE constraint demo on screen_bookings.
--     The constraint is built on a GiST index. Inserting an overlapping
--     booking is rejected by the database, not by application code.

-- A booking on a different screen does not collide with screen 1.
INSERT INTO screen_bookings (screen_id, booking) VALUES
    (2, tstzrange('2025-04-15 10:00+00', '2025-04-15 12:00+00', '[)'));
-- Success.

-- A non-overlapping booking on screen 1 (between the 12:00 and 14:00 slots)
-- is accepted: same screen, but no time overlap with existing rows.
INSERT INTO screen_bookings (screen_id, booking) VALUES
    (1, tstzrange('2025-04-15 12:30+00', '2025-04-15 13:30+00', '[)'));
-- Success.

-- The next insert overlaps with the existing 14:00-16:00 booking on
-- screen 1; the EXCLUDE constraint rejects it.
DO $$
BEGIN
    INSERT INTO screen_bookings (screen_id, booking) VALUES
        (1, tstzrange('2025-04-15 15:00+00', '2025-04-15 17:00+00', '[)'));
EXCEPTION WHEN exclusion_violation THEN
    RAISE NOTICE 'Exclusion violation: overlap rejected as expected.';
END $$;

-- (4) BRIN on view_events.event_at vs a B-tree on the same column.
--     This is the headline demo. The BRIN index is a few megabytes; the
--     B-tree on the same column is hundreds of megabytes or more. Both
--     serve the range query, but only one of them costs almost nothing.
CREATE INDEX idx_view_events_brin ON view_events USING BRIN (event_at);
CREATE INDEX idx_view_events_btree ON view_events (event_at);

SELECT
    indexrelname,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE relname = 'view_events'
ORDER BY pg_relation_size(indexrelid) DESC;

-- Force the planner to use BRIN, then B-tree, and compare.
SET enable_seqscan = off;

SET enable_bitmapscan = on;
SET enable_indexscan  = off;
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM view_events
WHERE event_at >= '2024-04-15'::timestamptz
  AND event_at <  '2024-04-16'::timestamptz;
-- Bitmap Index Scan via BRIN, with Recheck Cond and Rows Removed by Recheck.

SET enable_bitmapscan = off;
SET enable_indexscan  = on;
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM view_events
WHERE event_at >= '2024-04-15'::timestamptz
  AND event_at <  '2024-04-16'::timestamptz;
-- Index Scan via the B-tree.

RESET enable_seqscan;
RESET enable_bitmapscan;
RESET enable_indexscan;

-- The index sizes are the lesson. Drop the B-tree to see what the schema
-- would look like if we'd picked BRIN from the start.
DROP INDEX idx_view_events_btree;

-- (5) Hash index demo on sessions.token.
--     Equality lookups only. The Hash index stores a 4-byte hash per row,
--     no matter how long the token is.
CREATE INDEX idx_sessions_token_hash ON sessions USING HASH (token);

EXPLAIN (ANALYZE, BUFFERS)
SELECT user_id, expires_at FROM sessions
WHERE token = (SELECT token FROM sessions LIMIT 1);

-- A range query against the same column will not use the Hash index. The
-- planner has no choice but a sequential scan unless we add a B-tree.
EXPLAIN (ANALYZE, BUFFERS)
SELECT user_id FROM sessions WHERE token > 'a';
-- Seq Scan.

-- (6) pg_trgm GIN for substring/fuzzy matching on movies.title.
--     ILIKE with a leading wildcard normally cannot use a B-tree at all.
--     With a trigram GIN index, the planner can serve it.
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM movies WHERE title ILIKE '%inception%';
-- Seq Scan, no trigram index yet.

CREATE INDEX idx_movies_title_trgm_gin
    ON movies USING GIN (title gin_trgm_ops);

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM movies WHERE title ILIKE '%inception%';
-- Bitmap Index Scan via trigram GIN.

-- (7) pg_trgm GiST for ranked similarity (KNN order).
--     Same extension, different index type, different query pattern. GiST
--     supports the <-> distance operator for ordered nearest matches.
CREATE INDEX idx_movies_title_trgm_gist
    ON movies USING GIST (title gist_trgm_ops);

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title
FROM movies
WHERE title % 'inseption'
ORDER BY title <-> 'inseption'
LIMIT 5;
-- Index Scan via GiST trigram with Order By: title <-> 'inseption'.

-- (8) Bloom index for wide multi-attribute equality.
--     Any subset of the indexed columns can be the WHERE predicate. The
--     index returns a superset of candidates; the heap scan rechecks.
CREATE INDEX idx_event_attrs_bloom
    ON event_attributes
    USING BLOOM (region, device_class, plan, referrer, browser, os);

EXPLAIN (ANALYZE, BUFFERS)
SELECT event_id FROM event_attributes
WHERE region = 'EU' AND plan = 'pro' AND browser = 'chrome';

-- (9) GIN expression index for full-text search on review bodies.
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, body FROM reviews
WHERE to_tsvector('english', body) @@ to_tsquery('english', 'cinematography');
-- Seq Scan, no full-text index yet.

CREATE INDEX idx_reviews_body_fts
    ON reviews USING GIN (to_tsvector('english', body));

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, body FROM reviews
WHERE to_tsvector('english', body) @@ to_tsquery('english', 'cinematography');
-- Bitmap Index Scan via GIN expression index.

-- (10) An audit query for the schema's index portfolio.
--      Walk the list and ask, for each index, whether it matches the
--      shape of the queries that hit the table.
SELECT
    relname           AS table_name,
    indexrelname      AS index_name,
    pg_get_indexdef(indexrelid) AS definition,
    pg_size_pretty(pg_relation_size(indexrelid)) AS size,
    idx_scan          AS times_used
FROM pg_stat_user_indexes
ORDER BY relname, pg_relation_size(indexrelid) DESC;
