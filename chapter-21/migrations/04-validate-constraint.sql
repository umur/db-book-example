-- 04-validate-constraint.sql
--
-- The second half of the SET NOT NULL trick. VALIDATE CONSTRAINT scans
-- the table under SHARE UPDATE EXCLUSIVE, which does not block writes.
-- After this runs, Postgres knows every row satisfies the constraint
-- and the SET NOT NULL becomes a fast catalog change.
--
-- Pattern: subchapter 21.7 (Foreign keys and constraints).

SET lock_timeout = '5s';
SET statement_timeout = '0';

-- VALIDATE takes a weak lock; runs even with concurrent writes.
ALTER TABLE reviews VALIDATE CONSTRAINT reviews_flagged_not_null;

-- Now SET NOT NULL is a catalog change because the validation work is done.
ALTER TABLE reviews ALTER COLUMN flagged SET NOT NULL;

-- The helper constraint is no longer needed.
ALTER TABLE reviews DROP CONSTRAINT reviews_flagged_not_null;

-- Verify: the column is NOT NULL, the constraint is gone.
SELECT column_name, is_nullable
FROM information_schema.columns
WHERE table_name = 'reviews' AND column_name = 'flagged';

SELECT conname FROM pg_constraint
WHERE conrelid = 'reviews'::regclass;
