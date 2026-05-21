-- 05-create-index-concurrently.sql
--
-- Add an index without blocking writes. CREATE INDEX CONCURRENTLY
-- takes SHARE UPDATE EXCLUSIVE, which does not conflict with
-- ROW EXCLUSIVE (the lock that INSERT, UPDATE, DELETE take).
--
-- Note: CREATE INDEX CONCURRENTLY cannot run inside a BEGIN/COMMIT
-- block. It manages its own transaction internally and commits
-- between the two passes of the build.
--
-- Pattern: subchapter 21.6 (Creating and dropping indexes concurrently).

SET lock_timeout = '5s';
SET statement_timeout = '0';
SET maintenance_work_mem = '256MB';   -- speed up the build

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_reviews_flagged
    ON reviews (flagged)
    WHERE flagged = true;

-- Reset maintenance_work_mem so the rest of the session does not
-- inherit the elevated value. The setting is per-session, but leaving
-- it set hides itself from anyone who looks at the session later.
RESET maintenance_work_mem;

-- Always check for invalid indexes after a concurrent build.
-- A failed CREATE INDEX CONCURRENTLY leaves an invalid index in place
-- that consumes write overhead without helping reads.
SELECT
    schemaname,
    tablename,
    indexrelname AS indexname,
    indisvalid
FROM pg_stat_user_indexes
JOIN pg_index ON pg_index.indexrelid = pg_stat_user_indexes.indexrelid
WHERE NOT indisvalid;

-- The expected output: zero rows. Any invalid index here needs to be
-- dropped (DROP INDEX CONCURRENTLY) and rebuilt.
