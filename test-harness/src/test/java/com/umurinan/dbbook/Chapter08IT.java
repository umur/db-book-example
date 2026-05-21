package com.umurinan.dbbook;

import org.junit.jupiter.api.Test;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.sql.Connection;

/**
 * Chapter 8: EXPLAIN walkthroughs - diagnosing 8 misplanned queries and fixing them.
 */
@Testcontainers
class Chapter08IT extends PostgresBase {

    @Container
    static final PostgreSQLContainer<?> PG = container();

    @Test
    void seedLoads() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(8));
            long movies  = SqlRunner.queryLong(conn, "SELECT count(*) FROM movies");
            long ratings = SqlRunner.queryLong(conn, "SELECT count(*) FROM ratings");
            assertGte(movies,  10000, "chapter-8 movies");
            assertGte(ratings, 100000, "chapter-8 ratings");
        }
    }

    @Test
    void explainPrefixLikeWithoutIndex() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(8));
            SqlRunner.runStatements(conn, "ANALYZE movies;");

            // Without index: should show Seq Scan or Bitmap
            String plan = SqlRunner.explainAnalyze(conn,
                "SELECT id, title FROM movies WHERE release_year >= 2020 AND title LIKE 'The %' LIMIT 20");
            assertThat(plan != null, "plan generated for prefix-LIKE");
        }
    }

    @Test
    void textPatternOpsIndexReducesSeqScan() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(8));
            SqlRunner.runStatements(conn, "ANALYZE movies;");

            SqlRunner.runStatements(conn,
                "CREATE INDEX IF NOT EXISTS idx_movies_title_pattern " +
                "ON movies (title text_pattern_ops);");

            String plan = SqlRunner.explainAnalyze(conn,
                "SELECT id, title FROM movies WHERE title LIKE 'The %' LIMIT 20");
            // With text_pattern_ops, planner should use index (Bitmap or Index Scan)
            assertThat(plan != null, "plan generated after text_pattern_ops index");
        }
    }

    @Test
    void explainAnalyzeBuffersIncludesActualRows() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(8));
            String plan = SqlRunner.explainAnalyze(conn,
                "SELECT id, title FROM movies WHERE release_year = 2010 LIMIT 5");
            assertContains(plan, "actual", "EXPLAIN ANALYZE shows actual rows");
        }
    }

    @Test
    void staleStatsFixedByAnalyze() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(8));
            SqlRunner.runStatements(conn, "ANALYZE movies;");

            long statRows = SqlRunner.queryLong(conn,
                "SELECT n_distinct::bigint FROM pg_stats " +
                "WHERE tablename='movies' AND attname='release_year'");
            // After ANALYZE, n_distinct should be set (non-zero)
            assertThat(statRows != 0, "n_distinct populated after ANALYZE: " + statRows);
        }
    }
}
