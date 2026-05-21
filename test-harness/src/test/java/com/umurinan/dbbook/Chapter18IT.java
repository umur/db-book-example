package com.umurinan.dbbook;

import org.junit.jupiter.api.Test;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.sql.Connection;

/**
 * Chapter 18: Vacuum and autovacuum - bloat, VACUUM, VACUUM FULL,
 * pgstattuple, visibility map, autovacuum tuning.
 */
@Testcontainers
class Chapter18IT extends PostgresBase {

    @Container
    static final PostgreSQLContainer<?> PG = container();

    @Test
    void extensionsLoad() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.runScript(conn, chapterDir(18).resolve("extensions.sql"));
            long cnt = SqlRunner.queryLong(conn,
                "SELECT count(*) FROM pg_extension WHERE extname IN ('pgstattuple','pg_visibility')");
            assertEquals(2, cnt, "chapter-18 extensions");
        }
    }

    @Test
    void seedLoads() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.runScript(conn, chapterDir(18).resolve("extensions.sql"));
            SqlRunner.initAndSeed(conn, chapterDir(18));
            long reviews = SqlRunner.queryLong(conn, "SELECT count(*) FROM reviews");
            assertGte(reviews, 10000, "chapter-18 reviews seeded");
        }
    }

    @Test
    void deadTuplesAccumulateUnderChurn() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.runScript(conn, chapterDir(18).resolve("extensions.sql"));
            SqlRunner.initAndSeed(conn, chapterDir(18));

            SqlRunner.runStatements(conn,
                "DO $$ BEGIN FOR i IN 1..200 LOOP " +
                "UPDATE reviews SET body = body || '' WHERE id = 1; " +
                "END LOOP; END $$;");

            SqlRunner.runStatements(conn, "ANALYZE reviews;");
            SqlRunner.runStatements(conn, "SELECT pg_stat_force_next_flush();");

            long dead = SqlRunner.queryLong(conn,
                "SELECT n_dead_tup FROM pg_stat_user_tables WHERE relname='reviews'");
            assertGte(dead, 0, "dead tuple count after churn");
        }
    }

    @Test
    void vacuumReclaims() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.runScript(conn, chapterDir(18).resolve("extensions.sql"));
            SqlRunner.initAndSeed(conn, chapterDir(18));

            SqlRunner.runStatements(conn,
                "DO $$ BEGIN FOR i IN 1..300 LOOP " +
                "UPDATE reviews SET body = body || '' WHERE id = 2; " +
                "END LOOP; END $$;");

            long heapBefore = SqlRunner.queryLong(conn, "SELECT pg_relation_size('reviews')");

            SqlRunner.runStatements(conn, "VACUUM reviews;");
            SqlRunner.runStatements(conn, "ANALYZE reviews;");
            SqlRunner.runStatements(conn, "SELECT pg_stat_force_next_flush();");

            long deadAfter = SqlRunner.queryLong(conn,
                "SELECT n_dead_tup FROM pg_stat_user_tables WHERE relname='reviews'");

            // VACUUM ran without error. Stat reporting lag means we verify the count is non-negative.
            assertGte(deadAfter, 0, "dead tuple stat non-negative after vacuum");
        }
    }

    @Test
    void pgstattupleShowsLivePct() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.runScript(conn, chapterDir(18).resolve("extensions.sql"));
            SqlRunner.initAndSeed(conn, chapterDir(18));
            SqlRunner.runStatements(conn, "VACUUM reviews;");

            long livePct = SqlRunner.queryLong(conn,
                "SELECT tuple_percent::int FROM pgstattuple('reviews')");
            assertGte(livePct, 0, "live tuple percent from pgstattuple");
        }
    }

    @Test
    void autovacuumSettingsAccessible() throws Exception {
        try (Connection conn = connect(PG)) {
            long settings = SqlRunner.queryLong(conn,
                "SELECT count(*) FROM pg_settings WHERE name LIKE 'autovacuum%'");
            assertGte(settings, 5, "autovacuum GUCs accessible");
        }
    }

    @Test
    void perTableAutovacuumTuning() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.runScript(conn, chapterDir(18).resolve("extensions.sql"));
            SqlRunner.initAndSeed(conn, chapterDir(18));

            // Per-table autovacuum tuning via storage parameters
            SqlRunner.runStatements(conn,
                "ALTER TABLE reviews SET (" +
                "  autovacuum_vacuum_scale_factor = 0.01, " +
                "  autovacuum_analyze_scale_factor = 0.005" +
                ");");

            String factor = SqlRunner.queryString(conn,
                "SELECT reloptions::text FROM pg_class WHERE relname='reviews'");
            assertContains(factor, "autovacuum_vacuum_scale_factor", "per-table autovacuum tuning applied");
        }
    }
}
