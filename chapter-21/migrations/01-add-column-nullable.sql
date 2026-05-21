-- 01-add-column-nullable.sql
--
-- The first deploy: add a nullable column. Catalog change only.
-- ACCESS EXCLUSIVE is held for milliseconds.
--
-- Pattern: subchapter 21.4 (Adding and dropping columns safely).

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '0';

ALTER TABLE reviews ADD COLUMN flagged BOOLEAN;

COMMIT;

-- Verify: the column exists, every row has NULL.
SELECT count(*) AS total_reviews,
       count(flagged) AS non_null_flagged,
       count(*) - count(flagged) AS null_flagged
FROM reviews;
