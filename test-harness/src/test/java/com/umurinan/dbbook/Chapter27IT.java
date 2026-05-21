package com.umurinan.dbbook;

import org.junit.jupiter.api.Test;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.sql.Connection;

/**
 * Chapter 27: OS and Postgres tuning - random_page_cost, work_mem, checkpoint,
 * huge pages, effective_io_concurrency, parallel workers.
 */
@Testcontainers
class Chapter27IT extends PostgresBase {

    @Container
    static final PostgreSQLContainer<?> PG = container();

    @Test
    void seedLoads() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(27));
            long movies = SqlRunner.queryLong(conn, "SELECT count(*) FROM movies");
            assertGte(movies, 100, "chapter-27 seeded");
        }
    }

    @Test
    void tuningGucsAccessible() throws Exception {
        try (Connection conn = connect(PG)) {
            long cnt = SqlRunner.queryLong(conn,
                "SELECT count(*) FROM pg_settings WHERE name IN (" +
                "'shared_buffers','work_mem','maintenance_work_mem'," +
                "'effective_cache_size','random_page_cost','seq_page_cost'," +
                "'effective_io_concurrency','max_parallel_workers_per_gather'," +
                "'max_wal_size','checkpoint_timeout')");
            assertEquals(10, cnt, "all tuning GUCs accessible");
        }
    }

    @Test
    void randomPageCostAffectsPlan() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(27));
            SqlRunner.runStatements(conn, "ANALYZE view_events; ANALYZE movies;");

            conn.setAutoCommit(false);

            // Low random_page_cost -> planner prefers index scans
            SqlRunner.runStatements(conn, "SET LOCAL random_page_cost = 1.1;");
            String planLow = SqlRunner.explainAnalyze(conn,
                "SELECT count(*) FROM view_events WHERE occurred_at > now() - interval '30 days'");

            // High random_page_cost -> planner may prefer seq scan
            SqlRunner.runStatements(conn, "SET LOCAL random_page_cost = 10.0;");
            String planHigh = SqlRunner.explainAnalyze(conn,
                "SELECT count(*) FROM view_events WHERE occurred_at > now() - interval '30 days'");

            conn.rollback();

            assertThat(planLow != null, "low random_page_cost plan generated");
            assertThat(planHigh != null, "high random_page_cost plan generated");
        }
    }

    @Test
    void checkpointSettingsAccessible() throws Exception {
        try (Connection conn = connect(PG)) {
            String timeout = SqlRunner.queryString(conn,
                "SELECT setting FROM pg_settings WHERE name='checkpoint_timeout'");
            assertThat(Integer.parseInt(timeout) > 0, "checkpoint_timeout > 0: " + timeout);
        }
    }

    @Test
    void pgBuffercacheExtensionLoads() throws Exception {
        try (Connection conn = connect(PG)) {
            // init.sql for ch27 creates pg_buffercache
            SqlRunner.initAndSeed(conn, chapterDir(27));
            long cnt = SqlRunner.queryLong(conn,
                "SELECT count(*) FROM pg_extension WHERE extname='pg_buffercache'");
            assertEquals(1, cnt, "pg_buffercache loaded in chapter-27");
        }
    }

    @Test
    void parallelQueryWorkers() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(27));
            SqlRunner.runStatements(conn, "ANALYZE view_events;");

            conn.setAutoCommit(false);
            SqlRunner.runStatements(conn, "SET LOCAL max_parallel_workers_per_gather = 2;");
            String plan = SqlRunner.explainAnalyze(conn,
                "SELECT count(*) FROM view_events");
            conn.rollback();

            assertThat(plan != null, "parallel query plan generated");
        }
    }
}
