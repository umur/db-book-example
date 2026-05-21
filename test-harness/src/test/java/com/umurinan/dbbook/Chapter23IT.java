package com.umurinan.dbbook;

import org.junit.jupiter.api.Test;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.sql.Connection;

/**
 * Chapter 23: Streaming replication topology - cascade standby, recovery.conf
 * concepts, hot_standby, promote. Tests verify catalog and WAL APIs since a
 * full 3-node cluster is out of scope for this harness.
 */
@Testcontainers
class Chapter23IT extends PostgresBase {

    @Container
    static final PostgreSQLContainer<?> PG = container();

    @Test
    void seedLoads() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(23));
            long movies = SqlRunner.queryLong(conn, "SELECT count(*) FROM movies");
            assertGte(movies, 10, "chapter-23 seeded");
        }
    }

    @Test
    void hotStandbyGucAccessible() throws Exception {
        try (Connection conn = connect(PG)) {
            String hs = SqlRunner.queryString(conn,
                "SELECT setting FROM pg_settings WHERE name='hot_standby'");
            assertThat(hs != null, "hot_standby GUC accessible: " + hs);
        }
    }

    @Test
    void maxWalSendersGucAccessible() throws Exception {
        try (Connection conn = connect(PG)) {
            String mws = SqlRunner.queryString(conn,
                "SELECT setting FROM pg_settings WHERE name='max_wal_senders'");
            assertThat(Integer.parseInt(mws) > 0, "max_wal_senders > 0: " + mws);
        }
    }

    @Test
    void physicalSlotForCascade() throws Exception {
        try (Connection conn = connect(PG)) {
            // Simulate cascade slot creation
            try {
                SqlRunner.runStatements(conn,
                    "SELECT pg_drop_replication_slot('cascade_slot_ch23') " +
                    "FROM pg_replication_slots WHERE slot_name='cascade_slot_ch23';");
            } catch (Exception ignored) {}

            SqlRunner.runStatements(conn,
                "SELECT pg_create_physical_replication_slot('cascade_slot_ch23', true);");

            long cnt = SqlRunner.queryLong(conn,
                "SELECT count(*) FROM pg_replication_slots WHERE slot_name='cascade_slot_ch23'");
            assertEquals(1, cnt, "cascade replication slot created");

            SqlRunner.runStatements(conn,
                "SELECT pg_drop_replication_slot('cascade_slot_ch23');");
        }
    }

    @Test
    void replicationConflictSettingsAccessible() throws Exception {
        try (Connection conn = connect(PG)) {
            long cnt = SqlRunner.queryLong(conn,
                "SELECT count(*) FROM pg_settings " +
                "WHERE name IN ('max_standby_archive_delay','max_standby_streaming_delay')");
            assertEquals(2, cnt, "standby delay GUCs accessible");
        }
    }

    @Test
    void walReceiverStatAccessible() throws Exception {
        try (Connection conn = connect(PG)) {
            long rows = SqlRunner.queryLong(conn,
                "SELECT count(*) FROM pg_stat_wal_receiver");
            // 0 rows expected (this is primary), view must be queryable
            assertGte(rows, 0, "pg_stat_wal_receiver accessible");
        }
    }
}
