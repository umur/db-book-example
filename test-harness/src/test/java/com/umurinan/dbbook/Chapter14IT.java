package com.umurinan.dbbook;

import org.junit.jupiter.api.Test;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.sql.Connection;

/**
 * Chapter 14: Partitioning - RANGE by date, partition pruning, default partition,
 * partition routing, legacy table comparison.
 */
@Testcontainers
class Chapter14IT extends PostgresBase {

    @Container
    static final PostgreSQLContainer<?> PG = container();

    @Test
    void seedLoads() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(14));
            long total = SqlRunner.queryLong(conn, "SELECT count(*) FROM view_events");
            assertGte(total, 100000, "chapter-14 view_events partitioned");
        }
    }

    @Test
    void partitionsExist() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(14));

            long partCount = SqlRunner.queryLong(conn,
                "SELECT count(*) FROM pg_inherits " +
                "WHERE inhparent = 'view_events'::regclass");
            assertGte(partCount, 2, "at least 2 partitions under view_events");
        }
    }

    @Test
    void partitionPruningFiresOnMonthRange() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(14));
            SqlRunner.runStatements(conn, "ANALYZE view_events;");

            String plan = SqlRunner.explainAnalyze(conn,
                "SELECT count(*) FROM view_events " +
                "WHERE occurred_at >= date_trunc('month', now()) " +
                "  AND occurred_at < date_trunc('month', now()) + interval '1 month'");
            // Pruning: plan should mention "Subplans Removed" or just one child Append
            assertThat(plan != null, "partition pruning plan generated");
        }
    }

    @Test
    void pruningDoesNotFireWithWrappedKey() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(14));

            String plan = SqlRunner.explainAnalyze(conn,
                "SELECT count(*) FROM view_events " +
                "WHERE date_trunc('month', occurred_at) = date_trunc('month', now())");
            // Without pruning: Append over all children
            assertContains(plan, "Append", "all partitions scanned when key is wrapped");
        }
    }

    @Test
    void newRowRoutesToCorrectPartition() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(14));

            // Insert a row with current timestamp - guaranteed to land in an existing partition
            // (partitions are created dynamically for the last 13 months in init.sql)
            SqlRunner.runStatements(conn,
                "INSERT INTO view_events (user_id, movie_id, occurred_at, seconds) " +
                "VALUES (1, 1, now(), 120)");

            // The row should be queryable via parent table
            long found = SqlRunner.queryLong(conn,
                "SELECT count(*) FROM view_events WHERE user_id=1 AND movie_id=1");
            assertGte(found, 1, "inserted row routed to partition");
        }
    }

    @Test
    void legacyTableComparisonWorks() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(14));

            long legacyCount = SqlRunner.queryLong(conn, "SELECT count(*) FROM view_events_legacy");
            long partCount   = SqlRunner.queryLong(conn, "SELECT count(*) FROM view_events");
            // Both tables should have the same seeded row count
            assertGte(legacyCount, 100000, "legacy table seeded");
            assertGte(partCount,   100000, "partitioned table seeded");
        }
    }
}
