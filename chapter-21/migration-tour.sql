-- Chapter 21 migration tour.
--
-- The full zero-downtime rename of reviews.body to reviews.content,
-- run end-to-end with pg_locks queries between each step so the lock
-- acquisition is visible. This script does the work of subchapter 21.9.
--
-- Echo input/output so the comparisons are visible in the terminal log.
\set ECHO all

\ir init.sql
\ir seed.sql

-- ---------------------------------------------------------------------------
-- A small helper: show all locks held on the reviews table.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION show_reviews_locks() RETURNS TABLE (
    pid     INT,
    mode    TEXT,
    granted BOOLEAN,
    query_age INTERVAL,
    query   TEXT
) LANGUAGE sql AS $$
    SELECT
        a.pid,
        l.mode::text,
        l.granted,
        now() - a.query_start AS query_age,
        a.query
    FROM pg_locks l
    JOIN pg_stat_activity a USING (pid)
    JOIN pg_class c ON c.oid = l.relation
    WHERE c.relname = 'reviews'
    ORDER BY l.granted DESC, a.query_start;
$$;

-- ---------------------------------------------------------------------------
-- (0) Starting state. The reviews table has body, no content yet.
-- ---------------------------------------------------------------------------
\echo '== Starting state: reviews columns =='
SELECT column_name, is_nullable, data_type
FROM information_schema.columns
WHERE table_name = 'reviews'
ORDER BY ordinal_position;

\echo '== Locks on reviews (should be empty between sessions) =='
SELECT * FROM show_reviews_locks();

-- ---------------------------------------------------------------------------
-- (1) Add the shadow column nullable.
--
-- ACCESS EXCLUSIVE held for milliseconds; nothing else is touched.
-- ---------------------------------------------------------------------------
\echo '== (1) Add shadow column =='
BEGIN;
SET LOCAL lock_timeout = '5s';
ALTER TABLE reviews ADD COLUMN content TEXT;
\echo '   locks during the ALTER:'
SELECT * FROM show_reviews_locks();
COMMIT;

\echo '== After (1): both columns exist, content is null for every row =='
SELECT count(*)               AS total,
       count(body)            AS body_populated,
       count(content)         AS content_populated
FROM reviews;

-- ---------------------------------------------------------------------------
-- (2) Install the dual-write trigger.
--
-- From this point on, any write to body or content keeps both in sync.
-- ---------------------------------------------------------------------------
\echo '== (2) Install dual-write trigger =='
CREATE OR REPLACE FUNCTION sync_reviews_body_content() RETURNS trigger AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.content IS NULL THEN NEW.content := NEW.body;    END IF;
        IF NEW.body    IS NULL THEN NEW.body    := NEW.content; END IF;
    ELSIF TG_OP = 'UPDATE' THEN
        IF NEW.body    IS DISTINCT FROM OLD.body
           AND NEW.content IS NOT DISTINCT FROM OLD.content
        THEN
            NEW.content := NEW.body;
        ELSIF NEW.content IS DISTINCT FROM OLD.content
              AND NEW.body IS NOT DISTINCT FROM OLD.body
        THEN
            NEW.body := NEW.content;
        END IF;
    END IF;
    RETURN NEW;
END$$ LANGUAGE plpgsql;

CREATE TRIGGER reviews_sync_body_content
    BEFORE INSERT OR UPDATE ON reviews
    FOR EACH ROW EXECUTE FUNCTION sync_reviews_body_content();

-- Smoke test the trigger: insert a row with only body, content should fill in.
INSERT INTO reviews (user_id, movie_id, body)
VALUES (1, 1, 'trigger test row');

SELECT id, body, content
FROM reviews
WHERE body = 'trigger test row';

-- ---------------------------------------------------------------------------
-- (3) Backfill existing rows in chunks.
--
-- Each batch is a short transaction. Locks are bounded; autovacuum
-- has time between batches.
-- ---------------------------------------------------------------------------
\echo '== (3) Chunked backfill =='
DO $$
DECLARE
    rows_affected INT;
    total         INT := 0;
BEGIN
    LOOP
        UPDATE reviews
        SET content = body
        WHERE id IN (
            SELECT id FROM reviews
            WHERE content IS NULL
            ORDER BY id LIMIT 5000
        );
        GET DIAGNOSTICS rows_affected = ROW_COUNT;
        total := total + rows_affected;
        EXIT WHEN rows_affected = 0;
        RAISE NOTICE 'batch: % rows (total: %)', rows_affected, total;
        PERFORM pg_sleep(0.05);
    END LOOP;
    RAISE NOTICE 'backfill done: % rows', total;
END$$;

\echo '== After (3): every row has content =='
SELECT count(*)        AS total,
       count(content)  AS content_populated,
       count(*) - count(content) AS still_null
FROM reviews;

-- ---------------------------------------------------------------------------
-- (4) Application is now reading from content.
--
-- The application change is outside this script. From the database's
-- perspective, the next operation is the equivalent of step 5 of the
-- chapter: switch writes to content. Verify the trigger handles it.
-- ---------------------------------------------------------------------------
\echo '== (4 + 5) Smoke test: write to content, body should follow =='
UPDATE reviews
SET content = 'updated via content column'
WHERE body = 'trigger test row';

SELECT id, body, content
FROM reviews
WHERE content = 'updated via content column';

-- ---------------------------------------------------------------------------
-- (6) Drop the old column and the trigger.
--
-- The trigger goes first; otherwise the trigger function would
-- reference a column that no longer exists.
-- ---------------------------------------------------------------------------
\echo '== (6) Drop trigger and old column =='
BEGIN;
SET LOCAL lock_timeout = '5s';
DROP TRIGGER reviews_sync_body_content ON reviews;
DROP FUNCTION sync_reviews_body_content();
\echo '   locks while dropping trigger:'
SELECT * FROM show_reviews_locks();

ALTER TABLE reviews DROP COLUMN body;
\echo '   locks while dropping column:'
SELECT * FROM show_reviews_locks();

-- Promote content to NOT NULL using the NOT VALID trick.
ALTER TABLE reviews
    ADD CONSTRAINT reviews_content_not_null
    CHECK (content IS NOT NULL) NOT VALID;
COMMIT;

ALTER TABLE reviews VALIDATE CONSTRAINT reviews_content_not_null;
ALTER TABLE reviews ALTER COLUMN content SET NOT NULL;
ALTER TABLE reviews DROP CONSTRAINT reviews_content_not_null;

\echo '== Final state: only content column, NOT NULL =='
SELECT column_name, is_nullable, data_type
FROM information_schema.columns
WHERE table_name = 'reviews'
ORDER BY ordinal_position;

-- ---------------------------------------------------------------------------
-- Cleanup helper.
-- ---------------------------------------------------------------------------
DROP FUNCTION show_reviews_locks();

\echo '== Migration tour complete. =='
\echo '   The reviews.body column has been renamed to reviews.content'
\echo '   under live load. No long ACCESS EXCLUSIVE was ever held.'
