-- 07-rename-shadow-column.sql
--
-- The final step. The shadow column is the only column the application
-- writes to and reads from. The cosmetic rename gives it the canonical
-- name. RENAME COLUMN is a catalog change; ACCESS EXCLUSIVE for
-- milliseconds.
--
-- This step requires one more application deploy that switches the
-- read and write paths from `content` back to whatever the final name
-- is. Some teams skip the rename entirely and live with the shadow
-- name forever; the cosmetic name does not affect correctness.
--
-- Pattern: subchapter 21.9 (Cinetrack: zero-downtime rename).

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '0';

-- The chapter-21 scenario goes body -> content: the original column
-- is `body` and the shadow column we are migrating to is `content`.
-- After step 6 (drop the old `body` column), `content` is already the
-- final name, so this rename is a no-op in the sandbox. In a real
-- migration where the shadow column had a temporary name like
-- `content_new`, this is where you would rename it to the final name
-- (`content_new` -> `content`). Uncomment the line below to demonstrate
-- the rename mechanic on a column you actually want to rename.

-- ALTER TABLE reviews RENAME COLUMN content_new TO content;

COMMIT;

-- Verify the column list. The final shape of the table should have
-- `content` (or whatever the final name is) and not `body`.
SELECT column_name, is_nullable, data_type
FROM information_schema.columns
WHERE table_name = 'reviews'
ORDER BY ordinal_position;
