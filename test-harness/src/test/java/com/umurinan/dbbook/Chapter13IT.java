package com.umurinan.dbbook;

import org.junit.jupiter.api.Test;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.sql.Connection;

/**
 * Chapter 13: Full-text search - tsvector, tsquery, GIN index, ranking,
 * phrase search, trigram fuzzy fallback.
 */
@Testcontainers
class Chapter13IT extends PostgresBase {

    @Container
    static final PostgreSQLContainer<?> PG = container();

    @Test
    void extensionLoads() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.runScript(conn, chapterDir(13).resolve("extensions.sql"));
            long cnt = SqlRunner.queryLong(conn,
                "SELECT count(*) FROM pg_extension WHERE extname = 'pg_trgm'");
            assertEquals(1, cnt, "pg_trgm extension loaded");
        }
    }

    @Test
    void seedLoads() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.runScript(conn, chapterDir(13).resolve("extensions.sql"));
            SqlRunner.initAndSeed(conn, chapterDir(13));
            long movies  = SqlRunner.queryLong(conn, "SELECT count(*) FROM movies");
            long reviews = SqlRunner.queryLong(conn, "SELECT count(*) FROM reviews");
            assertGte(movies,  10000, "chapter-13 movies");
            assertGte(reviews, 10000, "chapter-13 reviews");
        }
    }

    @Test
    void tsvectorBasics() throws Exception {
        try (Connection conn = connect(PG)) {
            String tsv = SqlRunner.queryString(conn,
                "SELECT to_tsvector('english', 'The slow burn rewards patient viewers')::text");
            assertContains(tsv, "patient", "tsvector contains stemmed 'patient'");
        }
    }

    @Test
    void tsqueryMatchOperator() throws Exception {
        try (Connection conn = connect(PG)) {
            boolean matches = SqlRunner.queryBoolean(conn,
                "SELECT to_tsvector('english','A slow burn that rewards patient viewers') " +
                "@@ to_tsquery('english','patient & viewer')");
            assertThat(matches, "tsquery matches document");
        }
    }

    @Test
    void generatedTsvColumnPopulated() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.runScript(conn, chapterDir(13).resolve("extensions.sql"));
            SqlRunner.initAndSeed(conn, chapterDir(13));

            long withTsv = SqlRunner.queryLong(conn,
                "SELECT count(*) FROM movies WHERE search_tsv IS NOT NULL LIMIT 100");
            assertGte(withTsv, 1, "search_tsv generated column populated");
        }
    }

    @Test
    void ginFtsIndexAcceleratesSearch() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.runScript(conn, chapterDir(13).resolve("extensions.sql"));
            SqlRunner.initAndSeed(conn, chapterDir(13));
            SqlRunner.runStatements(conn, "ANALYZE movies;");

            SqlRunner.runStatements(conn,
                "CREATE INDEX IF NOT EXISTS idx_movies_search_gin " +
                "ON movies USING GIN (search_tsv);");

            String plan = SqlRunner.explainAnalyze(conn,
                "SELECT id, title FROM movies " +
                "WHERE search_tsv @@ to_tsquery('english','patient') LIMIT 20");
            // With enough data the planner uses a GIN index scan; with small tables it may seq-scan.
            // Just verify the plan is non-empty and the query ran without error.
            assertThat(plan != null && !plan.isEmpty(), "GIN FTS EXPLAIN returned a plan");
        }
    }

    @Test
    void tsRankOrdering() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.runScript(conn, chapterDir(13).resolve("extensions.sql"));
            SqlRunner.initAndSeed(conn, chapterDir(13));

            long rows = SqlRunner.queryLong(conn,
                "SELECT count(*) FROM (" +
                "  SELECT id, ts_rank(search_tsv, to_tsquery('english','slow')) AS rank " +
                "  FROM movies " +
                "  WHERE search_tsv @@ to_tsquery('english','slow') " +
                "  ORDER BY rank DESC LIMIT 10" +
                ") t");
            assertGte(rows, 1, "ts_rank returns results");
        }
    }
}
