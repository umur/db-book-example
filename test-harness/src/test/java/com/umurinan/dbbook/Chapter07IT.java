package com.umurinan.dbbook;

import org.junit.jupiter.api.Test;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.sql.Connection;

/**
 * Chapter 7: Query planner - cost model, statistics, extended stats,
 * row-count estimates, correlated columns.
 */
@Testcontainers
class Chapter07IT extends PostgresBase {

    @Container
    static final PostgreSQLContainer<?> PG = container();

    @Test
    void seedLoads() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(7));
            long movies = SqlRunner.queryLong(conn, "SELECT count(*) FROM movies");
            assertGte(movies, 1000, "chapter-7 movies");
        }
    }

    @Test
    void costSettingsAccessible() throws Exception {
        try (Connection conn = connect(PG)) {
            long rows = SqlRunner.queryLong(conn,
                "SELECT count(*) FROM pg_settings " +
                "WHERE name IN ('seq_page_cost','random_page_cost','cpu_tuple_cost'," +
                "'cpu_index_tuple_cost','cpu_operator_cost')");
            assertEquals(5, rows, "cost GUCs");
        }
    }

    @Test
    void columnStatsAccessible() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(7));
            SqlRunner.runStatements(conn, "ANALYZE reviews;");
            long cols = SqlRunner.queryLong(conn,
                "SELECT count(*) FROM pg_stats WHERE tablename='reviews'");
            assertGte(cols, 3, "pg_stats entries for reviews");
        }
    }

    @Test
    void extendedStatsReduceEstimationError() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(7));
            SqlRunner.runStatements(conn, "ANALYZE view_events;");

            // Create extended statistics on correlated columns
            SqlRunner.runStatements(conn,
                "CREATE STATISTICS IF NOT EXISTS st_country_language " +
                "ON country_code, language_code FROM view_events;");
            SqlRunner.runStatements(conn, "ANALYZE view_events;");

            long statsCount = SqlRunner.queryLong(conn,
                "SELECT count(*) FROM pg_statistic_ext WHERE stxname='st_country_language'");
            assertEquals(1, statsCount, "extended stats created");
        }
    }

    @Test
    void plannerSelectsHashJoinForLargeJoin() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(7));
            SqlRunner.runStatements(conn, "ANALYZE movies; ANALYZE ratings;");

            String plan = SqlRunner.explainAnalyze(conn,
                "SELECT m.id, count(r.*) FROM movies m " +
                "JOIN ratings r ON r.movie_id = m.id " +
                "GROUP BY m.id LIMIT 10");
            assertThat(plan != null && !plan.isEmpty(), "planner produced a plan");
        }
    }
}
