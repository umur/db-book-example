package com.umurinan.dbbook;

import org.junit.jupiter.api.Test;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.sql.Connection;

/**
 * Chapter 22: Physical replication - streaming standby, replication slots,
 * WAL senders, lag monitoring. Tests run against a single Postgres instance
 * (no actual standby) and verify the replication infrastructure catalog views.
 */
@Testcontainers
class Chapter22IT extends PostgresBase {

    @Container
    static final PostgreSQLContainer<?> PG = container();

    @Test
    void seedLoads() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(22));
            long movies = SqlRunner.queryLong(conn, "SELECT count(*) FROM movies");
            assertGte(movies, 10, "chapter-22 seeded");
        }
    }

    @Test
    void walLevelSupportsReplication() throws Exception {
        try (Connection conn = connect(PG)) {
            String level = SqlRunner.queryString(conn,
                "SELECT setting FROM pg_settings WHERE name='wal_level'");
            assertThat("replica".equals(level) || "logical".equals(level),
                "wal_level supports replication: " + level);
        }
    }

    @Test
    void replicationSlotCanBeCreated() throws Exception {
        try (Connection conn = connect(PG)) {
            // Drop if exists
            try {
                SqlRunner.runStatements(conn,
                    "SELECT pg_drop_replication_slot('test_slot_ch22') " +
                    "FROM pg_replication_slots WHERE slot_name='test_slot_ch22';");
            } catch (Exception ignored) {}

            SqlRunner.runStatements(conn,
                "SELECT pg_create_physical_replication_slot('test_slot_ch22', true);");

            long slots = SqlRunner.queryLong(conn,
                "SELECT count(*) FROM pg_replication_slots WHERE slot_name='test_slot_ch22'");
            assertEquals(1, slots, "replication slot created");

            // Cleanup
            SqlRunner.runStatements(conn,
                "SELECT pg_drop_replication_slot('test_slot_ch22');");
        }
    }

    @Test
    void pgStatReplicationViewAccessible() throws Exception {
        try (Connection conn = connect(PG)) {
            long rows = SqlRunner.queryLong(conn,
                "SELECT count(*) FROM pg_stat_replication");
            // No standby in test environment so rows=0 is fine; view must be accessible
            assertGte(rows, 0, "pg_stat_replication view accessible");
        }
    }

    @Test
    void currentWalLsnAndSegmentAccessible() throws Exception {
        try (Connection conn = connect(PG)) {
            String lsn = SqlRunner.queryString(conn, "SELECT pg_current_wal_lsn()::text");
            String seg = SqlRunner.queryString(conn,
                "SELECT pg_walfile_name(pg_current_wal_lsn())");
            assertThat(lsn != null && lsn.contains("/"), "LSN format valid");
            assertThat(seg != null && seg.length() > 10, "WAL segment name valid: " + seg);
        }
    }

    @Test
    void walSenderProcessCountAccessible() throws Exception {
        try (Connection conn = connect(PG)) {
            long senders = SqlRunner.queryLong(conn,
                "SELECT count(*) FROM pg_stat_activity WHERE backend_type='walsender'");
            assertGte(senders, 0, "wal senders query ran");
        }
    }
}
