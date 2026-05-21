package com.umurinan.dbbook;

import org.junit.jupiter.api.Test;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.sql.Connection;

/**
 * Chapter 16: Concurrency patterns - SKIP LOCKED queue, optimistic locking
 * with version column, idempotency keys, counter aggregation.
 */
@Testcontainers
class Chapter16IT extends PostgresBase {

    @Container
    static final PostgreSQLContainer<?> PG = container();

    @Test
    void seedLoads() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(16));
            long movies = SqlRunner.queryLong(conn, "SELECT count(*) FROM movies");
            assertGte(movies, 50, "chapter-16 seeded");
        }
    }

    @Test
    void skipLockedClaimesDifferentRows() throws Exception {
        try (Connection conn1 = connect(PG);
             Connection conn2 = connect(PG)) {
            SqlRunner.initAndSeed(conn1, chapterDir(16));

            conn1.setAutoCommit(false);
            conn2.setAutoCommit(false);

            // conn1 claims first pending job
            String id1 = SqlRunner.queryString(conn1,
                "SELECT id::text FROM jobs WHERE status='pending' " +
                "ORDER BY created_at LIMIT 1 FOR UPDATE SKIP LOCKED");

            // conn2 should get a different job (or null if only 1 job)
            String id2 = SqlRunner.queryString(conn2,
                "SELECT id::text FROM jobs WHERE status='pending' " +
                "ORDER BY created_at LIMIT 1 FOR UPDATE SKIP LOCKED");

            conn1.rollback();
            conn2.rollback();

            // If there were at least 2 jobs, they should be different
            if (id1 != null && id2 != null) {
                assertThat(!id1.equals(id2), "SKIP LOCKED returns different rows");
            }
            // If only 1 job, id2 is null - that's correct SKIP LOCKED behavior
            assertThat(true, "SKIP LOCKED did not block");
        }
    }

    @Test
    void optimisticLockingVersionColumn() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(16));

            // reviews table has a version column in ch16
            long vBefore = SqlRunner.queryLong(conn,
                "SELECT version FROM reviews WHERE id = 1");

            int updated = 0;
            try (var st = conn.createStatement()) {
                updated = st.executeUpdate(
                    "UPDATE reviews SET body = body || '.', version = version + 1 " +
                    "WHERE id = 1 AND version = " + vBefore);
            }
            assertEquals(1, updated, "optimistic lock update affected 1 row");

            long vAfter = SqlRunner.queryLong(conn,
                "SELECT version FROM reviews WHERE id = 1");
            assertEquals(vBefore + 1, vAfter, "version incremented");
        }
    }

    @Test
    void idempotencyKeyPreventsDoubleSend() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(16));

            String key = "test-idempotency-key-" + System.nanoTime();
            // Use raw JDBC so duplicate key errors are NOT swallowed by SqlRunner
            try (var st = conn.createStatement()) {
                st.execute("INSERT INTO idempotency_keys (key, request_hash) VALUES ('"
                    + key + "', 'hash1')");
            }

            // Second insert must conflict on primary key
            boolean conflicted = false;
            try (var st = conn.createStatement()) {
                st.execute("INSERT INTO idempotency_keys (key, request_hash) VALUES ('"
                    + key + "', 'hash1')");
            } catch (java.sql.SQLException e) {
                conflicted = e.getMessage() != null && e.getMessage().contains("duplicate key");
            }
            assertThat(conflicted, "duplicate idempotency key rejected");
        }
    }

    @Test
    void counterAggregationPattern() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(16));

            // movies has rating_count and rating_sum columns
            SqlRunner.runStatements(conn,
                "UPDATE movies SET rating_count = rating_count + 1, " +
                "rating_sum = rating_sum + 8 WHERE id = 1");

            long count = SqlRunner.queryLong(conn,
                "SELECT rating_count FROM movies WHERE id = 1");
            assertGte(count, 1, "rating_count incremented");
        }
    }
}
