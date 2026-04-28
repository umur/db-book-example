-- Chapter 24 logical replication tour.
--
-- Walks through the full upgrade scenario from subchapter 24.4 plus the
-- row-filter and column-list demos from subchapter 24.3.
--
-- This script is meant to be run interactively, switching between two
-- psql sessions: one connected to the Postgres 15 publisher (port 5415)
-- and one connected to the Postgres 17 subscriber (port 5417). The
-- comments mark which session to use for each block.
--
-- Echo input/output so the comparisons are visible.
\set ECHO all

-- ---------------------------------------------------------------------------
-- (1) On the publisher (port 5415): create the publication.
--
-- Lists tables explicitly. FOR ALL TABLES is dangerous on a cluster
-- under active development.
-- ---------------------------------------------------------------------------
\echo '== (1) Publisher: create the publication =='
CREATE PUBLICATION cinetrack_pub
    FOR TABLE movies, users, ratings, reviews;

\echo '== Confirm the publication exists =='
SELECT pubname, puballtables, pubinsert, pubupdate, pubdelete
FROM pg_publication
WHERE pubname = 'cinetrack_pub';

-- ---------------------------------------------------------------------------
-- (2) On the subscriber (port 5417): create the subscription.
--
-- The subscriber's tables must already exist (run init.sql first). The
-- CONNECTION string points back to the publisher; "publisher" is the
-- service name in the docker-compose file.
-- ---------------------------------------------------------------------------
\echo '== (2) Subscriber: create the subscription =='
CREATE SUBSCRIPTION cinetrack_sub
    CONNECTION 'host=publisher dbname=cinetrack user=cinetrack_replica password=cinetrack_replica'
    PUBLICATION cinetrack_pub;

-- ---------------------------------------------------------------------------
-- (3) On the subscriber: watch the initial copy state machine.
--
-- Every table moves through i (init) -> d (data copy) -> f (finished
-- copy) -> s (synchronized) -> r (ready). Re-run this query a few
-- times to see the progression.
-- ---------------------------------------------------------------------------
\echo '== (3) Subscriber: subscription state machine =='
SELECT
    s.subname,
    c.relname,
    sr.srsubstate,
    pg_size_pretty(pg_relation_size(sr.srrelid)) AS size
FROM pg_subscription_rel sr
JOIN pg_subscription s ON s.oid = sr.srsubid
JOIN pg_class c ON c.oid = sr.srrelid
ORDER BY sr.srsubstate, c.relname;

-- ---------------------------------------------------------------------------
-- (4) On the publisher: confirm replay lag.
--
-- replay_bytes is the byte distance between the publisher's current WAL
-- and what the subscriber has replayed. Below 1MB means the subscriber
-- is keeping up.
-- ---------------------------------------------------------------------------
\echo '== (4) Publisher: replay lag for active subscribers =='
SELECT
    application_name,
    client_addr,
    state,
    pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS replay_bytes,
    write_lag,
    flush_lag,
    replay_lag
FROM pg_stat_replication;

-- ---------------------------------------------------------------------------
-- (5) On the publisher: ongoing replication smoke test.
--
-- Insert a row and watch it appear on the subscriber within a few
-- milliseconds. Run the SELECT on the subscriber after the insert.
-- ---------------------------------------------------------------------------
\echo '== (5) Publisher: insert a row to test ongoing replication =='
INSERT INTO reviews (user_id, movie_id, body)
VALUES (1, 1, 'Logical replication smoke test row.');

\echo '   on the subscriber, run:'
\echo '   SELECT id, body FROM reviews ORDER BY id DESC LIMIT 1;'

-- ---------------------------------------------------------------------------
-- (6) On the publisher: cutover sequence resync.
--
-- Logical replication does not replicate sequence values. Before
-- cutover, generate setval statements from the publisher and pipe them
-- into the subscriber. Run this query on the publisher and capture the
-- output to a file, then \i the file on the subscriber.
-- ---------------------------------------------------------------------------
\echo '== (6) Publisher: generate setval statements for the subscriber =='
SELECT format(
    'SELECT setval(%L, %s);',
    quote_ident(schemaname) || '.' || quote_ident(sequencename),
    COALESCE(last_value, start_value)
) AS setval_sql
FROM pg_sequences
WHERE schemaname NOT IN ('pg_catalog', 'information_schema');

-- ---------------------------------------------------------------------------
-- (7) Cutover cleanup: on the subscriber, disable and drop the subscription.
--
-- The slot_name = NONE step is the one that prevents DROP SUBSCRIPTION
-- from trying to also drop the publisher-side slot. Drop the publisher
-- slot manually afterwards.
-- ---------------------------------------------------------------------------
\echo '== (7) Subscriber: clean up after cutover =='
\echo '   ALTER SUBSCRIPTION cinetrack_sub DISABLE;'
\echo '   ALTER SUBSCRIPTION cinetrack_sub SET (slot_name = NONE);'
\echo '   DROP SUBSCRIPTION cinetrack_sub;'
\echo '   then on the publisher:'
\echo "   SELECT pg_drop_replication_slot('cinetrack_sub');"

-- ---------------------------------------------------------------------------
-- (8) On the publisher: row-filter demo (subchapter 24.3).
--
-- A separate publication that ships only EU rows. Pair it with a fresh
-- subscription on the subscriber side to see the filter take effect.
-- ---------------------------------------------------------------------------
\echo '== (8) Publisher: row-filter publication =='
CREATE PUBLICATION cinetrack_pub_eu
    FOR TABLE
        users   WHERE (region = 'eu'),
        reviews WHERE (region = 'eu');

\echo '   to test, on a fresh subscriber:'
\echo "   CREATE SUBSCRIPTION cinetrack_sub_eu"
\echo "       CONNECTION 'host=publisher dbname=cinetrack user=cinetrack_replica password=cinetrack_replica'"
\echo "       PUBLICATION cinetrack_pub_eu;"
\echo '   then count: only EU users and their reviews should arrive.'

-- ---------------------------------------------------------------------------
-- (9) On the publisher: column-list demo (subchapter 24.3).
--
-- Reporting publication that drops the email column from users and the
-- body column from reviews. The replica identity (id) must be in every
-- column list.
-- ---------------------------------------------------------------------------
\echo '== (9) Publisher: column-list publication =='
CREATE PUBLICATION cinetrack_pub_reporting
    FOR TABLE
        users   (id, username, region, created_at),
        reviews (id, user_id, movie_id, posted_at);

\echo '   subscribers to this publication never see emails or review text.'

-- ---------------------------------------------------------------------------
-- (10) On either side: monitor for stuck apply workers.
--
-- A subscription that has stopped because of a conflict or a missing
-- column will have its apply worker process gone from
-- pg_stat_subscription. This is the query to alert on.
-- ---------------------------------------------------------------------------
\echo '== (10) Subscriber: apply worker health =='
SELECT
    subname,
    pid,
    received_lsn,
    latest_end_lsn,
    last_msg_send_time,
    last_msg_receipt_time,
    now() - last_msg_receipt_time AS staleness
FROM pg_stat_subscription;

\echo '== Logical tour complete. =='
\echo '   Tear it all down with `docker compose down -v` for a fresh start.'
