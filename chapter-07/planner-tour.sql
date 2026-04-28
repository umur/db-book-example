-- Chapter 7 planner tour.
-- Run top to bottom against a freshly seeded chapter-7 cinetrack database.
-- Each numbered section maps to a moment in the chapter prose.
-- Don't worry yet about reading every line of EXPLAIN output; chapter 8 is
-- the full plan-reading guide. Here, the goal is to watch the planner's
-- estimates change as inputs change.

-- (1) The five cost knobs the cost model is built on.
SHOW seq_page_cost;
SHOW random_page_cost;
SHOW cpu_tuple_cost;
SHOW cpu_index_tuple_cost;
SHOW cpu_operator_cost;

-- (2) What ANALYZE collected for the reviews table.
--     Read this column by column. n_distinct, MCV count, histogram bucket
--     count, and correlation are the four numbers that drive most plans.
SELECT attname,
       null_frac,
       n_distinct,
       array_length(most_common_vals, 1)  AS mcv_count,
       array_length(histogram_bounds, 1)  AS hist_buckets,
       correlation
FROM pg_stats
WHERE tablename  = 'reviews'
  AND schemaname = 'public'
ORDER BY attname;

-- A tighter look at the first 10 entries pg_stats has about reviews.
SELECT * FROM pg_stats WHERE tablename = 'reviews' LIMIT 10;

-- (3) A query the planner gets right.
--     One column, well-distributed values, fresh statistics.
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM view_events WHERE country_code = 'US';
-- Estimate vs. actual rows should be close. Plan is straightforward.

-- (4) A query the planner gets wrong (correlated columns).
--     country and language are correlated by design. The planner doesn't
--     know yet, so it multiplies per-column selectivities and gets a
--     row estimate that is far below the actual count.
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*)
FROM view_events
WHERE country_code = 'US'
  AND language_code = 'en';
-- Look at "rows=" (estimate) vs "actual rows=" in the seq scan filter.
-- The planner under-estimates by roughly a third: it computes
-- selectivity as 0.40 * 0.67 ~= 0.27, but every US row is also "en"
-- (except for a small noise fraction), so reality is close to 0.40.

-- (5) Fix it: extended statistics with all three kinds.
CREATE STATISTICS IF NOT EXISTS view_events_country_lang
    (dependencies, ndistinct, mcv)
    ON country_code, language_code
    FROM view_events;

ANALYZE view_events;

-- Look at what was learned.
SELECT statistics_name,
       attnames,
       kinds,
       n_distinct,
       dependencies
FROM pg_stats_ext
WHERE statistics_name = 'view_events_country_lang';

-- Re-run the same query and watch the estimate snap into place.
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*)
FROM view_events
WHERE country_code = 'US'
  AND language_code = 'en';
-- The "rows=" estimate is now close to "actual rows=".
-- Plan shape may change (different join methods elsewhere when used in
-- a bigger query), but the estimate accuracy is the diagnostic win.

-- (6) Adjusting random_page_cost for the session and watching plans flip.
--     A query with selective filter that the planner could satisfy with
--     either an index scan or a sequential scan. The cost ratio decides.
EXPLAIN
SELECT id, occurred_at
FROM view_events
WHERE country_code = 'JP'
ORDER BY occurred_at DESC
LIMIT 100;
-- Note the chosen plan: probably an index scan on country, then a sort,
-- because we lowered selectivity on JP rows.

SET random_page_cost = 8.0;
EXPLAIN
SELECT id, occurred_at
FROM view_events
WHERE country_code = 'JP'
ORDER BY occurred_at DESC
LIMIT 100;
-- Random reads are now twice as expensive. The planner may switch to
-- a bitmap heap scan or even a sequential scan for the same query.

SET random_page_cost = 1.1;
EXPLAIN
SELECT id, occurred_at
FROM view_events
WHERE country_code = 'JP'
ORDER BY occurred_at DESC
LIMIT 100;
-- Random reads are now nearly free. The planner reaches for the index.

RESET random_page_cost;

-- (7) enable_seqscan = off as a diagnostic tool, never a fix.
--     Run a query the planner picks a sequential scan for, then watch
--     what happens when seq scans get a giant cost penalty.
EXPLAIN
SELECT count(*) FROM view_events WHERE language_code = 'en';
-- Likely a sequential scan: language='en' matches a huge fraction.

SET enable_seqscan = off;

EXPLAIN
SELECT count(*) FROM view_events WHERE language_code = 'en';
-- Now an index scan or bitmap scan with a much higher cost.
-- The planner picked the right thing originally; we just proved it.

RESET enable_seqscan;

-- (8) Per-column statistics target on a skewed column.
--     Raise the target on movie_id, ANALYZE, see the MCV list grow.
SELECT attname,
       array_length(most_common_vals, 1) AS mcv_count
FROM pg_stats
WHERE tablename = 'reviews' AND attname = 'movie_id';

ALTER TABLE reviews ALTER COLUMN movie_id SET STATISTICS 1000;
ANALYZE reviews;

SELECT attname,
       array_length(most_common_vals, 1) AS mcv_count
FROM pg_stats
WHERE tablename = 'reviews' AND attname = 'movie_id';
-- The MCV count grows from <=100 to up to 1000 if the data has the
-- distinct-value count to support it. Selectivity estimates for
-- "movie_id = ?" are now much more accurate at the long tail.

-- Reset for cleanliness.
ALTER TABLE reviews ALTER COLUMN movie_id SET STATISTICS DEFAULT;
ANALYZE reviews;

-- (9) effective_cache_size: not memory, just an estimate.
--     The planner uses it to decide whether index lookups will hit cache.
SHOW effective_cache_size;
-- Default at startup. Compare to your machine's actual RAM and the OS
-- cache budget; section 7.6 has the rule of thumb.

-- (10) The planner's view of view_events as a relation.
SELECT relname,
       reltuples,
       relpages,
       pg_size_pretty(pg_relation_size(oid)) AS heap_size
FROM pg_class
WHERE relname = 'view_events';
-- These two numbers (reltuples, relpages) are the inputs to most cost
-- estimates against the table. They get refreshed by ANALYZE and VACUUM.
