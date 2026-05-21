-- 03-add-not-null-constraint-not-valid.sql
--
-- The first half of the SET NOT NULL trick. Add a CHECK constraint
-- that says the column is not null, but mark it NOT VALID so Postgres
-- skips the table scan up front. The catalog update is a millisecond
-- of ACCESS EXCLUSIVE.
--
-- Pattern: subchapter 21.7 (Foreign keys and constraints).

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '0';

ALTER TABLE reviews
    ADD CONSTRAINT reviews_flagged_not_null
    CHECK (flagged IS NOT NULL) NOT VALID;

COMMIT;

-- Verify: the constraint exists but is not yet validated.
SELECT conname, convalidated
FROM pg_constraint
WHERE conrelid = 'reviews'::regclass
  AND conname = 'reviews_flagged_not_null';
