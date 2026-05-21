-- Chapter 6 index tour.
-- Run top to bottom against a freshly seeded cinetrack database.
-- Each numbered section maps to a moment in the chapter prose.
--
-- Run extensions.sql first so pageinspect, pgstattuple, and pg_visibility
-- are available.

\ir extensions.sql
\ir init.sql
\ir seed.sql

-- (1) The starting point: no index on ratings.movie_id.
--     A query that filters by movie_id has to scan the whole table.
--     Look for "Seq Scan on ratings" in the plan. The total cost is the
--     cost of reading every page of the heap.
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, score
FROM ratings
WHERE movie_id = 17;

-- (2) Build the index. Same query, completely different plan.
--     "Index Scan using idx_ratings_movie_id". Buffers shows index pages
--     plus a small number of heap pages, instead of every heap page.
CREATE INDEX idx_ratings_movie_id ON ratings (movie_id);

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, score
FROM ratings
WHERE movie_id = 17;

-- (3) Index-only scan: cover every column the query reads.
--     The two-column index includes both movie_id and score, so the query
--     can be answered without visiting the heap. The first run usually
--     shows non-zero heap fetches because the visibility map isn't set
--     yet. The next section fixes that.
CREATE INDEX idx_ratings_movie_id_score ON ratings (movie_id, score);

EXPLAIN (ANALYZE, BUFFERS)
SELECT movie_id, score
FROM ratings
WHERE movie_id = 17;
-- Look for "Index Only Scan" and "Heap Fetches: N".

-- (4) Vacuum sets the visibility map. Re-run the index-only scan and
--     watch Heap Fetches drop, often to 0.
VACUUM (VERBOSE) ratings;

EXPLAIN (ANALYZE, BUFFERS)
SELECT movie_id, score
FROM ratings
WHERE movie_id = 17;
-- Heap Fetches: 0 (or close to it).

-- (5) The visibility map, directly. pg_visibility_map returns one row per
--     heap page with all_visible and all_frozen flags.
SELECT all_visible, all_frozen, count(*)
FROM pg_visibility_map('ratings')
GROUP BY all_visible, all_frozen
ORDER BY 1 DESC, 2 DESC;
-- After VACUUM most pages should show all_visible = true.

-- (6) B-tree internals: the metapage. bt_metap returns the root page,
--     tree level (height - 1), and bookkeeping fields.
SELECT * FROM bt_metap('idx_ratings_movie_id');

-- (7) B-tree internals: per-page stats. Page 1 is usually the root or
--     a high-level internal page on a tree this size.
SELECT blkno, type, live_items, dead_items, avg_item_size, page_size,
       free_size, btpo_prev, btpo_next, btpo_level
FROM bt_page_stats('idx_ratings_movie_id', 1);
-- type = 'r' for root, 'i' for internal, 'l' for leaf, 'd' for deleted.

-- (8) Index density and fragmentation across the whole index.
--     leaf_fragmentation should be low and avg_leaf_density high
--     (~90%) on a freshly built index.
SELECT * FROM pgstatindex('idx_ratings_movie_id');

-- (9) Watch index bloat happen. Update enough rows enough times that
--     dead pointers actually accumulate beyond the 8 KB rounding floor of
--     pg_relation_size. Each update changes score (an indexed column on
--     idx_ratings_movie_id_score), so HOT does not apply: every updated
--     tuple gets a fresh index entry, and the old entry stays until
--     vacuum runs.
DO $$
BEGIN
    FOR i IN 1..50 LOOP
        UPDATE ratings SET score = ((score + 1) % 10) + 1
        WHERE movie_id BETWEEN 1 AND 5000;
    END LOOP;
END$$;

-- Now the visibility map drops back, and the index has dead entries.
SELECT all_visible, count(*)
FROM pg_visibility_map('ratings')
GROUP BY all_visible
ORDER BY 1 DESC;

SELECT pg_size_pretty(pg_relation_size('idx_ratings_movie_id_score'))
       AS index_size,
       (SELECT avg_leaf_density FROM pgstatindex('idx_ratings_movie_id_score'))
       AS leaf_density;

-- (10) REINDEX CONCURRENTLY rebuilds without an exclusive lock. Compare
--      the size before and after.
REINDEX INDEX CONCURRENTLY idx_ratings_movie_id_score;

SELECT pg_size_pretty(pg_relation_size('idx_ratings_movie_id_score'))
       AS index_size_after,
       (SELECT avg_leaf_density FROM pgstatindex('idx_ratings_movie_id_score'))
       AS leaf_density_after;
