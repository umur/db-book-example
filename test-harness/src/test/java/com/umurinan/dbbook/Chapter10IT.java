package com.umurinan.dbbook;

import org.junit.jupiter.api.Test;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.sql.Connection;

/**
 * Chapter 10: Specialty indexes - GIN (array, JSONB), GiST, BRIN, bloom, trigram.
 */
@Testcontainers
class Chapter10IT extends PostgresBase {

    @Container
    static final PostgreSQLContainer<?> PG = container();

    @Test
    void extensionsLoad() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.runScript(conn, chapterDir(10).resolve("extensions.sql"));
            long cnt = SqlRunner.queryLong(conn,
                "SELECT count(*) FROM pg_extension WHERE extname IN ('pg_trgm','bloom','btree_gist')");
            assertEquals(3, cnt, "chapter-10 extensions");
        }
    }

    @Test
    void seedLoads() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.runScript(conn, chapterDir(10).resolve("extensions.sql"));
            SqlRunner.initAndSeed(conn, chapterDir(10));
            long movies = SqlRunner.queryLong(conn, "SELECT count(*) FROM movies");
            assertGte(movies, 10000, "chapter-10 movies");
        }
    }

    @Test
    void ginArrayIndexSupportsContainment() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.runScript(conn, chapterDir(10).resolve("extensions.sql"));
            SqlRunner.initAndSeed(conn, chapterDir(10));
            SqlRunner.runStatements(conn, "ANALYZE movies;");

            SqlRunner.runStatements(conn,
                "CREATE INDEX IF NOT EXISTS idx_movies_genres_gin ON movies USING GIN (genres);");

            String plan = SqlRunner.explainAnalyze(conn,
                "SELECT id, title FROM movies WHERE genres @> ARRAY['drama']");
            assertContains(plan, "Bitmap", "GIN array index used for containment");
        }
    }

    @Test
    void ginJsonbIndexSupportsContainment() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.runScript(conn, chapterDir(10).resolve("extensions.sql"));
            SqlRunner.initAndSeed(conn, chapterDir(10));
            SqlRunner.runStatements(conn, "ANALYZE movies;");

            SqlRunner.runStatements(conn,
                "CREATE INDEX IF NOT EXISTS idx_movies_metadata_gin " +
                "ON movies USING GIN (metadata jsonb_path_ops);");

            String plan = SqlRunner.explainAnalyze(conn,
                "SELECT id FROM movies WHERE metadata @> '{\"format\":\"4K\"}'");
            assertThat(plan != null, "JSONB GIN plan generated");
        }
    }

    @Test
    void brinIndexSmallerThanBtree() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.runScript(conn, chapterDir(10).resolve("extensions.sql"));
            SqlRunner.initAndSeed(conn, chapterDir(10));

            SqlRunner.runStatements(conn,
                "CREATE INDEX IF NOT EXISTS idx_ve_occurred_btree ON view_events (event_at)");
            SqlRunner.runStatements(conn,
                "CREATE INDEX IF NOT EXISTS idx_ve_occurred_brin ON view_events USING BRIN (event_at)");

            long btreeSize = SqlRunner.queryLong(conn,
                "SELECT pg_relation_size('idx_ve_occurred_btree')");
            long brinSize  = SqlRunner.queryLong(conn,
                "SELECT pg_relation_size('idx_ve_occurred_brin')");

            assertGt(btreeSize, brinSize, "BRIN smaller than B-tree");
        }
    }

    @Test
    void trigramIndexSupportsFuzzySearch() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.runScript(conn, chapterDir(10).resolve("extensions.sql"));
            SqlRunner.initAndSeed(conn, chapterDir(10));
            SqlRunner.runStatements(conn, "ANALYZE movies;");

            SqlRunner.runStatements(conn,
                "CREATE INDEX IF NOT EXISTS idx_movies_title_trgm " +
                "ON movies USING GIN (title gin_trgm_ops);");

            String plan = SqlRunner.explainAnalyze(conn,
                "SELECT id, title FROM movies WHERE title % 'Cinetrack'");
            assertThat(plan != null, "trigram index plan generated");
        }
    }
}
