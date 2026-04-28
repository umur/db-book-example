-- 02-backfill-chunked.sql
--
-- Backfill the new column in chunks. Each batch is a short transaction
-- with bounded row locks; autovacuum runs between batches; the WAL
-- writer keeps up.
--
-- Pattern: subchapter 21.8 (Large data backfills).
--
-- The seed table has 200 rows, so the loop will run exactly one batch,
-- update all of them, and exit on the next iteration with rows_affected = 0.
-- That means the pg_sleep(0.1) below fires once before exit and never
-- between meaningful batches in this sandbox. On a real production table
-- the loop would run thousands of times and the sleep would matter.

DO $$
DECLARE
    rows_affected INT;
    batch_size    INT := 5000;
    total         INT := 0;
BEGIN
    LOOP
        UPDATE reviews
        SET flagged = false
        WHERE id IN (
            SELECT id FROM reviews
            WHERE flagged IS NULL
            ORDER BY id
            LIMIT batch_size
        );
        GET DIAGNOSTICS rows_affected = ROW_COUNT;
        total := total + rows_affected;
        EXIT WHEN rows_affected = 0;
        RAISE NOTICE 'backfilled batch of % rows (total: %)', rows_affected, total;
        PERFORM pg_sleep(0.1);
    END LOOP;
    RAISE NOTICE 'backfill complete: % rows updated', total;
END$$;

-- Verify: every row should have a value.
SELECT count(*) AS total_reviews,
       count(flagged) AS non_null_flagged,
       count(*) - count(flagged) AS null_flagged
FROM reviews;
