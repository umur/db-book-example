-- Chapter 13 full-text search tour.
-- Run top to bottom against a freshly seeded cinetrack database.
-- Each numbered section maps to a moment in the chapter prose.

-- (1) tsvector basics.
--     to_tsvector tokenizes, stems, and drops stop words.
--     The result is a sorted lexeme list with positions.
SELECT to_tsvector('english',
    'The slow burn rewards patient viewers who keep watching.');

-- (2) tsquery basics and the @@ match operator.
--     Stemming bridges the gap: the document says 'viewers', the query
--     says 'viewer', the lexemes both reduce to 'viewer'.
SELECT to_tsvector('english', 'A slow burn that rewards patient viewers')
       @@ to_tsquery('english', 'patient & viewer')                AS matches,
       phraseto_tsquery('english', 'patient viewer')               AS phrase_query,
       websearch_to_tsquery('english', 'patient -boring "slow burn"') AS websearch_query;

-- (3) GIN-indexed tsvector lookup against the stored search_tsv column.
--     Compare the plan to a naive WHERE to_tsvector(body) @@ q in section (10).
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, body
FROM reviews
WHERE search_tsv @@ to_tsquery('english', 'patient & viewer')
LIMIT 10;

-- (4) Weighted multi-column tsvector on movies.
--     Title is weight A, director is weight C. See section 13.4 for the
--     generated-column definition this query is reading from.
SELECT id, title, director, search_tsv
FROM movies
WHERE search_tsv @@ websearch_to_tsquery('english', 'samurai kurosawa')
LIMIT 5;

-- (5) ts_rank_cd with weight vector and length normalization.
--     The default weights {0.1, 0.2, 0.4, 1.0} run D, C, B, A.
--     Normalization 32 divides the rank by itself + 1, squashing
--     scores into the 0-1 range. Flag 1 divides by 1 + log(document
--     length). The two can be OR'd together: 1|32 = 33.
WITH q AS (
    SELECT websearch_to_tsquery('english', 'samurai kurosawa') AS query
)
SELECT m.id, m.title, m.director,
       ts_rank_cd('{0.1, 0.2, 0.4, 1.0}', m.search_tsv, q.query, 32) AS rank
FROM movies m, q
WHERE m.search_tsv @@ q.query
ORDER BY rank DESC, m.release_year DESC
LIMIT 10;

-- (6) Trigram similarity for fuzzy matching.
--     A misspelled name like 'kurasawa' produces no FTS match because the
--     stemmer never produces that lexeme. pg_trgm gets us close anyway.
SELECT id, title, director, similarity(director, 'kurasawa') AS sim
FROM movies
WHERE director % 'kurasawa'
ORDER BY sim DESC
LIMIT 10;

-- (7) Combined: FTS first, trigram fallback for the rows FTS missed.
--     The trigram leg is scaled down by 0.5 so legitimate FTS hits
--     outrank fuzzy matches when both are present.
WITH fts AS (
    SELECT id, title, director,
           ts_rank_cd(search_tsv,
                      websearch_to_tsquery('english', 'kurasawa samurai'),
                      32) AS rank
    FROM movies
    WHERE search_tsv @@ websearch_to_tsquery('english', 'kurasawa samurai')
),
trgm AS (
    SELECT id, title, director,
           greatest(similarity(title,    'kurasawa samurai'),
                    similarity(director, 'kurasawa samurai')) * 0.5 AS rank
    FROM movies
    WHERE (title    % 'kurasawa samurai'
        OR director % 'kurasawa samurai')
      AND id NOT IN (SELECT id FROM fts)
)
SELECT id, title, director, rank, 'fts'  AS source FROM fts
UNION ALL
SELECT id, title, director, rank, 'trgm'        FROM trgm
ORDER BY rank DESC
LIMIT 25;

-- (8) Cross-table search: movies ranked by their best matching review,
--     combined with their own title-and-director rank.
WITH q AS (
    SELECT websearch_to_tsquery('english', 'patient cinematography') AS query
),
review_matches AS (
    SELECT r.movie_id,
           max(ts_rank_cd(r.search_tsv, q.query, 32)) AS review_rank
    FROM reviews r, q
    WHERE r.search_tsv @@ q.query
    GROUP BY r.movie_id
),
title_matches AS (
    SELECT m.id AS movie_id,
           ts_rank_cd(m.search_tsv, q.query, 32) AS title_rank
    FROM movies m, q
    WHERE m.search_tsv @@ q.query
)
SELECT m.id, m.title, m.director,
       coalesce(rm.review_rank, 0) +
       2.0 * coalesce(tm.title_rank, 0) AS rank
FROM movies m
LEFT JOIN review_matches rm ON rm.movie_id = m.id
LEFT JOIN title_matches  tm ON tm.movie_id = m.id
WHERE rm.movie_id IS NOT NULL OR tm.movie_id IS NOT NULL
ORDER BY rank DESC
LIMIT 25;

-- (9) ts_headline for highlighted snippets.
--     Run on the small candidate set, not the whole table; ts_headline
--     is not index-supported.
WITH q AS (
    SELECT websearch_to_tsquery('english', 'patient burn') AS query
)
SELECT m.title,
       ts_headline('english', r.body, q.query,
                   'StartSel=<b>, StopSel=</b>, MaxFragments=2, FragmentDelimiter=...')
FROM reviews r
JOIN movies  m ON m.id = r.movie_id
JOIN q ON true
WHERE r.search_tsv @@ q.query
LIMIT 5;

-- (10) Language config switching.
--     Same body, two configs, two tokenizations. The 'simple' config
--     skips stemming and stop-word removal; useful for slugs and SKUs.
SELECT to_tsvector('english', 'The patient viewers were watching') AS english,
       to_tsvector('simple',  'The patient viewers were watching') AS simple;

-- (11) The wrong way: calling to_tsvector in WHERE.
--     Compare the plan against section (3). This one cannot use the
--     GIN index because the indexed expression is search_tsv, not
--     to_tsvector(body). Sequential scan, every row tokenized.
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, body
FROM reviews
WHERE to_tsvector('english', body) @@ to_tsquery('english', 'patient & viewer')
LIMIT 10;

-- (12) Inspecting search index sizes.
--     A useful sanity check after a backfill. GIN indexes on tsvectors
--     run ~30% of the underlying table; trigram GINs are smaller because
--     the indexed columns are short.
SELECT relname, indexrelname,
       pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
       idx_scan
FROM pg_stat_user_indexes
WHERE indexrelname IN (
    'idx_movies_search_tsv',
    'idx_reviews_search_tsv',
    'idx_movies_title_trgm',
    'idx_movies_director_trgm'
)
ORDER BY pg_relation_size(indexrelid) DESC;
