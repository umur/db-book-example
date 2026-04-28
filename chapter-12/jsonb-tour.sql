-- Chapter 12 JSONB tour.
-- Run top to bottom against a freshly seeded cinetrack database.
-- Each numbered section maps to a moment in the chapter prose.

-- (1) Operator demo.
--     -> returns JSONB, ->> returns text. @> is containment, ? is key
--     existence. jsonb_path_query reaches into the document.
SELECT
    metadata -> 'director'              AS director_jsonb,
    metadata ->> 'director'             AS director_text,
    metadata -> 'languages'             AS languages_jsonb,
    metadata -> 'languages' ->> 0       AS first_language,
    metadata ? 'awards'                 AS has_awards_key,
    metadata @> '{"languages": ["en"]}' AS speaks_english,
    jsonb_path_query(metadata, '$.awards[*].name')
                                        AS award_names
FROM movies WHERE id = 7;

-- (2) Containment without an index: sequential scan.
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM movies
WHERE metadata @> '{"languages": ["fr"]}';
-- Seq Scan, ~38 ms on 50k rows.

-- (3) GIN index with the default jsonb_ops opclass.
--     Indexes every key and every value. Supports @>, ?, ?|, ?&, @?, @@.
CREATE INDEX idx_movies_metadata_gin
    ON movies USING GIN (metadata);

-- Same containment query: now a Bitmap Index Scan.
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM movies
WHERE metadata @> '{"languages": ["fr"]}';

-- Key-existence query: only jsonb_ops can serve this, not jsonb_path_ops.
EXPLAIN (ANALYZE, BUFFERS)
SELECT id FROM movies WHERE metadata ? 'awards';

-- Compare execution time and rows from the previous EXPLAIN against this
-- one. Index size halved; query latency should be similar for @> lookups.
-- This is the side-by-side comparison the chapter promised: same query,
-- two opclasses, look at the plan and the timing on each.

-- (4) Drop the default index and try jsonb_path_ops.
--     Smaller, faster, but only supports @>.
DROP INDEX idx_movies_metadata_gin;

CREATE INDEX idx_movies_metadata_path_gin
    ON movies USING GIN (metadata jsonb_path_ops);

-- Containment still served, plan looks the same.
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM movies
WHERE metadata @> '{"languages": ["fr"]}';

-- Compare the two opclasses' on-disk size.
-- (Recreate jsonb_ops temporarily so you can compare, then drop it.)
CREATE INDEX idx_movies_metadata_gin
    ON movies USING GIN (metadata);

SELECT
    indexname,
    pg_size_pretty(pg_relation_size(indexname::regclass)) AS size
FROM pg_indexes
WHERE tablename = 'movies'
  AND indexname LIKE 'idx_movies_metadata%'
ORDER BY indexname;
-- jsonb_ops is roughly twice the size of jsonb_path_ops on the same data.

DROP INDEX idx_movies_metadata_gin;

-- (5) Containment query on a more nested fragment.
--     "Movies that won an Oscar for Cinematography." The right side is a
--     partial document; anything not specified is unconstrained.
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM movies
WHERE metadata @> '{"awards": [{"name": "Oscar", "category": "Cinematography"}]}';

-- (6) Path-query for the case containment can't express.
--     Multi-condition predicate per array element with an OR.
--     The default GIN (jsonb_ops) supports the @? operator; jsonb_path_ops
--     does not. Path queries with the function form (jsonb_path_exists)
--     work without an index but pay the sequential scan.
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM movies
WHERE jsonb_path_exists(metadata,
        '$.awards[*] ? (@.year >= 2011
                        && (@.category == "Cinematography"
                         || @.category == "Sound"))');

-- (7) Expression index for a hot single key.
--     The query uses ->> equality, which the GIN index does not serve.
--     A B-tree on the extracted text is the right tool.
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM movies
WHERE metadata ->> 'director' = 'C. Nolan';
-- Without the expression index, this is a sequential scan.

CREATE INDEX idx_movies_metadata_director
    ON movies ((metadata ->> 'director'));

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM movies
WHERE metadata ->> 'director' = 'C. Nolan';
-- Now an Index Scan against the expression index.

-- Compare index sizes.
SELECT
    indexname,
    pg_size_pretty(pg_relation_size(indexname::regclass)) AS size
FROM pg_indexes
WHERE tablename = 'movies'
  AND indexname IN ('idx_movies_metadata_path_gin',
                    'idx_movies_metadata_director')
ORDER BY indexname;
-- The expression index is roughly a tenth the size of the GIN index.

-- (8) Range query on a JSONB-extracted value.
--     A B-tree expression index serves range queries. GIN does not.
CREATE INDEX idx_movies_metadata_aspect
    ON movies (((metadata #>> '{format, aspect_ratio}')));

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM movies
WHERE metadata #>> '{format, aspect_ratio}' = '2.39:1';

-- (9) jsonb_set: mutating a nested key.
--     The whole row is rewritten; every JSONB index updates its posting
--     lists. Watch the wall-clock cost of this on a wide-indexed column.
UPDATE movies
SET metadata = jsonb_set(metadata, '{production, country}', '"UK"')
WHERE id = 1;

SELECT id, metadata #> '{production}' FROM movies WHERE id = 1;

-- Concatenation: right side wins on conflicting keys.
UPDATE movies
SET metadata = metadata || '{"reissue_year": 2020}'
WHERE id = 1;

-- Delete a key.
UPDATE movies
SET metadata = metadata - 'reissue_year'
WHERE id = 1;

-- (10) Schema migration: lift a hot JSONB key into a real column.
--      The expression index from step (7) was a staging step; this is
--      the destination.
ALTER TABLE movies
    ADD COLUMN production_country TEXT;

UPDATE movies
SET production_country = metadata #>> '{production, country}';

CREATE INDEX idx_movies_country_year
    ON movies (production_country, release_year DESC);

-- The query rewrites: no extraction, no JSONB, plain B-tree.
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title FROM movies
WHERE production_country = 'US'
ORDER BY release_year DESC
LIMIT 50;

-- (11) The full picture: which indexes does the table now have?
SELECT
    indexname,
    pg_size_pretty(pg_relation_size(indexname::regclass)) AS size,
    indexdef
FROM pg_indexes
WHERE tablename = 'movies'
ORDER BY indexname;

-- (12) Audit query for unused JSONB indexes.
--      Any GIN index on a JSONB column with idx_scan = 0 after a
--      representative week is a strong drop candidate. The write tax
--      is paying for nothing.
SELECT
    relname           AS table_name,
    indexrelname      AS index_name,
    idx_scan          AS times_used,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE relname = 'movies'
ORDER BY idx_scan ASC, pg_relation_size(indexrelid) DESC;
