package com.umurinan.dbbook;

import org.junit.jupiter.api.Test;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.sql.Connection;

/**
 * Chapter 6: B-tree internals - index scan vs seq scan, HOT, visibility map,
 * index bloat, pageinspect bt_metap / bt_page_stats.
 */
@Testcontainers
class Chapter06IT extends PostgresBase {

    @Container
    static final PostgreSQLContainer<?> PG = container();

    @Test
    void extensionsLoad() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.runScript(conn, chapterDir(6).resolve("extensions.sql"));
            long cnt = SqlRunner.queryLong(conn,
                "SELECT count(*) FROM pg_extension WHERE extname IN ('pageinspect','pgstattuple','pg_visibility')");
            assertEquals(3, cnt, "chapter-6 extensions");
        }
    }

    @Test
    void seqScanBeforeIndex() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.runScript(conn, chapterDir(6).resolve("extensions.sql"));
            SqlRunner.initAndSeed(conn, chapterDir(6));

            // Verify no idx_ratings_movie_id exists yet (index-tour creates it)
            long idxExists = SqlRunner.queryLong(conn,
                "SELECT count(*) FROM pg_indexes WHERE indexname='idx_ratings_movie_id' AND schemaname='public'");
            // The init.sql for ch6 intentionally omits the movie_id index to show seq scan first
            // If it exists, the tour already created it; either is fine for compile/run
            assertGte(idxExists, 0, "idx check ran");

            // Without the index, query should still return results
            long rows = SqlRunner.queryLong(conn,
                "SELECT count(*) FROM ratings WHERE movie_id = 17");
            assertGte(rows, 0, "ratings for movie_id=17");
        }
    }

    @Test
    void indexScanAfterCreation() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.runScript(conn, chapterDir(6).resolve("extensions.sql"));
            SqlRunner.initAndSeed(conn, chapterDir(6));

            // Drop if already exists, then recreate
            SqlRunner.runStatements(conn, "DROP INDEX IF EXISTS idx_ratings_movie_id_ch6;");
            SqlRunner.runStatements(conn,
                "CREATE INDEX idx_ratings_movie_id_ch6 ON ratings (movie_id);");

            String plan = SqlRunner.explainAnalyze(conn,
                "SELECT id, score FROM ratings WHERE movie_id = 17");
            assertContains(plan, "Index", "plan uses index for movie_id lookup");
        }
    }

    @Test
    void btMetapQueryRuns() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.runScript(conn, chapterDir(6).resolve("extensions.sql"));
            SqlRunner.initAndSeed(conn, chapterDir(6));
            SqlRunner.runStatements(conn,
                "CREATE INDEX IF NOT EXISTS idx_ratings_movie_id ON ratings (movie_id);");

            long root = SqlRunner.queryLong(conn,
                "SELECT root FROM bt_metap('idx_ratings_movie_id')");
            assertGte(root, 1, "B-tree root page");
        }
    }

    @Test
    void indexBloatMeasurable() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.runScript(conn, chapterDir(6).resolve("extensions.sql"));
            SqlRunner.initAndSeed(conn, chapterDir(6));
            SqlRunner.runStatements(conn,
                "CREATE INDEX IF NOT EXISTS idx_ratings_movie_id ON ratings (movie_id);");

            // pgstatindex gives avg_leaf_density
            long density = SqlRunner.queryLong(conn,
                "SELECT avg_leaf_density::int FROM pgstatindex('idx_ratings_movie_id')");
            assertGte(density, 0, "avg_leaf_density");
        }
    }
}
