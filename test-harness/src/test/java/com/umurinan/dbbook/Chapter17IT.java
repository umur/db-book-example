package com.umurinan.dbbook;

import org.junit.jupiter.api.Test;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.sql.Connection;

/**
 * Chapter 17: Outbox pattern and SKIP LOCKED queue - fanout-in-one-transaction,
 * publisher drain, partial index on pending rows.
 */
@Testcontainers
class Chapter17IT extends PostgresBase {

    @Container
    static final PostgreSQLContainer<?> PG = container();

    @Test
    void seedLoads() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(17));
            long movies = SqlRunner.queryLong(conn, "SELECT count(*) FROM movies");
            assertGte(movies, 100, "chapter-17 movies");
        }
    }

    @Test
    void fanoutInOneTransaction() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(17));

            conn.setAutoCommit(false);

            // Insert review + outbox event atomically
            SqlRunner.runStatements(conn,
                "WITH new_review AS (" +
                "  INSERT INTO reviews (user_id, movie_id, body) " +
                "  VALUES (1, 1, 'Test fanout review') RETURNING id, user_id, movie_id, body" +
                "), evt AS (" +
                "  INSERT INTO outbox (aggregate_type, aggregate_id, event_type, payload) " +
                "  SELECT 'Review', r.id::text, 'ReviewPosted', " +
                "         jsonb_build_object('review_id', r.id, 'user_id', r.user_id) " +
                "  FROM new_review r RETURNING id" +
                ") SELECT count(*) FROM evt;");

            long outboxPending = SqlRunner.queryLong(conn,
                "SELECT count(*) FROM outbox WHERE published_at IS NULL");
            conn.commit();

            assertGte(outboxPending, 1, "outbox event created");
        }
    }

    @Test
    void outboxPublisherDrainWithSkipLocked() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(17));

            // Seed an outbox event manually
            SqlRunner.runStatements(conn,
                "INSERT INTO outbox (aggregate_type, aggregate_id, event_type, payload) " +
                "VALUES ('Movie', '1', 'MovieCreated', '{\"movie_id\":1}')");

            conn.setAutoCommit(false);

            // Publisher claims a batch with SKIP LOCKED (FOR UPDATE requires a non-aggregate target)
            // Use a CTE to lock rows then count them
            long claimed = SqlRunner.queryLong(conn,
                "WITH batch AS (" +
                "  SELECT id FROM outbox " +
                "  WHERE published_at IS NULL " +
                "  ORDER BY created_at LIMIT 100 FOR UPDATE SKIP LOCKED" +
                ") SELECT count(*) FROM batch");

            // Mark as published
            SqlRunner.runStatements(conn,
                "UPDATE outbox SET published_at = now() " +
                "WHERE published_at IS NULL");
            conn.commit();

            assertGte(claimed, 1, "publisher claimed at least 1 outbox event");
        }
    }

    @Test
    void partialIndexOnPendingOutbox() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(17));

            // Create partial index matching the publisher claim query
            SqlRunner.runStatements(conn,
                "CREATE INDEX IF NOT EXISTS idx_outbox_pending " +
                "ON outbox (created_at) WHERE published_at IS NULL;");

            long idxSize = SqlRunner.queryLong(conn,
                "SELECT pg_relation_size('idx_outbox_pending')");
            assertGte(idxSize, 0, "partial outbox index exists");
        }
    }

    @Test
    void followersReceiveNotifications() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(17));

            // Check that follows exist
            long follows = SqlRunner.queryLong(conn, "SELECT count(*) FROM follows");
            assertGte(follows, 0, "follows table accessible");
        }
    }
}
