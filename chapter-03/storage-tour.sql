-- Chapter 3 storage tour.
-- Run top to bottom against a freshly seeded cinetrack database.
-- Each numbered section maps to a moment in the chapter prose.

-- (1) Page header for page 0 of the reviews heap.
--     lower/upper bound the free-space gap. The difference is bytes free.
SELECT lsn, lower, upper, special, pagesize, version
FROM page_header(get_raw_page('reviews', 0));

-- (2) Line pointers and tuple metadata for page 0.
--     lp_flags: 1 = normal, 2 = redirect (HOT chain head), 3 = dead, 0 = unused.
--     t_ctid: self-pointer for live tuples, forwarding pointer inside HOT chains.
SELECT lp, lp_off, lp_flags, lp_len,
       t_xmin, t_xmax, t_ctid,
       t_infomask, t_infomask2
FROM heap_page_items(get_raw_page('reviews', 0))
LIMIT 10;

-- (3) Tuple-level statistics for the whole heap.
--     tuple_percent should be high; dead_tuple_percent low; free_percent
--     reflects fillfactor.
SELECT * FROM pgstattuple('reviews');

-- (4) Find the TOAST table associated with reviews.
--     For short bodies, toast_size is small; for large bodies it grows.
SELECT c.relname AS heap,
       t.relname AS toast,
       pg_size_pretty(pg_relation_size(c.oid))           AS heap_size,
       pg_size_pretty(pg_relation_size(t.oid))           AS toast_size,
       pg_size_pretty(pg_total_relation_size(c.oid))     AS total
FROM pg_class c
LEFT JOIN pg_class t ON t.oid = c.reltoastrelid
WHERE c.relname = 'reviews';

-- (5) Free-space map: pages with the most room for new tuples.
SELECT blkno, avail
FROM pg_freespace('reviews')
ORDER BY avail DESC
LIMIT 5;

-- (6) HOT update demo. The body column is not indexed, so an UPDATE on
--     body is HOT-eligible. Watch n_tup_hot_upd rise.
-- pg_stat_force_next_flush() drains this backend's pending stat updates so
-- pg_stat_user_tables shows current numbers; pg_stat_clear_snapshot() forces
-- this session to refetch from the cumulative stats system.
ANALYZE reviews;
SELECT pg_stat_force_next_flush();
SELECT pg_stat_clear_snapshot();
SELECT n_tup_upd, n_tup_hot_upd,
       round(100.0 * n_tup_hot_upd / NULLIF(n_tup_upd, 0), 1) AS hot_pct
FROM pg_stat_user_tables WHERE relname = 'reviews';

DO $$
BEGIN
    FOR i IN 1..200 LOOP
        UPDATE reviews SET body = body || ' ' WHERE id = (i % 50) + 1;
    END LOOP;
END $$ LANGUAGE plpgsql;

ANALYZE reviews;
SELECT pg_stat_force_next_flush();
SELECT pg_stat_clear_snapshot();
SELECT n_tup_upd, n_tup_hot_upd,
       round(100.0 * n_tup_hot_upd / NULLIF(n_tup_upd, 0), 1) AS hot_pct,
       pg_size_pretty(pg_relation_size('reviews')) AS heap
FROM pg_stat_user_tables WHERE relname = 'reviews';

-- (7) Look at the page after the churn. Expect line pointers in state 2
--     (redirect) and state 1 (live) on pages where HOT chains formed.
SELECT lp_flags, count(*) AS slots
FROM heap_page_items(get_raw_page('reviews', 0))
GROUP BY lp_flags
ORDER BY lp_flags;

-- (8) Break HOT by updating an indexed column. movie_id is in
--     idx_reviews_movie_id, so this is non-HOT.
SELECT pg_stat_force_next_flush();
SELECT pg_stat_clear_snapshot();
SELECT n_tup_upd, n_tup_hot_upd FROM pg_stat_user_tables WHERE relname = 'reviews';

UPDATE reviews SET movie_id = 2 WHERE id = 1;
UPDATE reviews SET movie_id = 1 WHERE id = 1;

ANALYZE reviews;
SELECT pg_stat_force_next_flush();
SELECT pg_stat_clear_snapshot();
SELECT n_tup_upd, n_tup_hot_upd FROM pg_stat_user_tables WHERE relname = 'reviews';
-- n_tup_upd went up; n_tup_hot_upd did not. Index entry was rewritten.

-- (9) Adjust fillfactor on reviews and rewrite the table to apply.
--     pg_repack is the production-friendly equivalent on busy tables.
SELECT relname, reloptions FROM pg_class WHERE relname = 'reviews';

ALTER TABLE reviews SET (fillfactor = 80);
VACUUM FULL reviews;

SELECT relname, reloptions FROM pg_class WHERE relname = 'reviews';

-- Run the same churn pattern as step (6). With 20% reserved on every
-- page, HOT updates should land on the same page far more often.
ANALYZE reviews;
SELECT pg_stat_force_next_flush();
SELECT pg_stat_clear_snapshot();
SELECT n_tup_upd, n_tup_hot_upd FROM pg_stat_user_tables WHERE relname = 'reviews';

DO $$
BEGIN
    FOR i IN 1..200 LOOP
        UPDATE reviews SET body = body || ' ' WHERE id = (i % 50) + 1;
    END LOOP;
END $$ LANGUAGE plpgsql;

ANALYZE reviews;
SELECT pg_stat_force_next_flush();
SELECT pg_stat_clear_snapshot();
SELECT n_tup_upd, n_tup_hot_upd,
       round(100.0 * n_tup_hot_upd / NULLIF(n_tup_upd, 0), 1) AS hot_pct,
       pg_size_pretty(pg_relation_size('reviews')) AS heap
FROM pg_stat_user_tables WHERE relname = 'reviews';

-- (10) Approximate stats for big tables. Cheap enough to run on a schedule.
SELECT * FROM pgstattuple_approx('reviews');
