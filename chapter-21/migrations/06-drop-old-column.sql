-- 06-drop-old-column.sql
--
-- After the application has fully switched to the new column and any
-- rollback window has passed, drop the old column. DROP COLUMN is a
-- catalog change. ACCESS EXCLUSIVE is held for milliseconds; the
-- column data on disk stays until vacuum or a rewrite reclaims it.
--
-- This script also drops the trigger and function that kept the two
-- columns in sync during the migration. Drop the trigger BEFORE
-- dropping the column, or the trigger function will reference a
-- column that no longer exists.
--
-- Pattern: subchapter 21.9 (Cinetrack: zero-downtime rename).

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '0';

-- Drop the trigger first.
DROP TRIGGER IF EXISTS reviews_sync_body_content ON reviews;
DROP FUNCTION IF EXISTS sync_reviews_body_content();

-- Now safe to drop the old column.
ALTER TABLE reviews DROP COLUMN IF EXISTS body;

COMMIT;

-- Verify: the column is gone and the trigger is gone.
SELECT column_name FROM information_schema.columns
WHERE table_name = 'reviews'
ORDER BY ordinal_position;

SELECT tgname FROM pg_trigger
WHERE tgrelid = 'reviews'::regclass AND NOT tgisinternal;
