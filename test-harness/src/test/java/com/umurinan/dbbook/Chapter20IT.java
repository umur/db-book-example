package com.umurinan.dbbook;

import org.junit.jupiter.api.Test;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.sql.Connection;
import java.util.List;

/**
 * Chapter 20: Monitoring - pg_stat_statements, pg_buffercache, slow query
 * detection, home-feed regression diagnosis.
 *
 * Requires shared_preload_libraries=pg_stat_statements at server start.
 * The container is started with withCommand so the preload is in effect
 * before the extension is created and before any queries are captured.
 */
@Testcontainers
class Chapter20IT extends PostgresBase {

    @Container
    static final PostgreSQLContainer<?> PG = new PostgreSQLContainer<>(IMAGE)
            .withDatabaseName("cinetrack")
            .withUsername("cinetrack")
            .withPassword("cinetrack")
            .withCommand(
                    "postgres",
                    "-c", "shared_preload_libraries=pg_stat_statements",
                    "-c", "pg_stat_statements.max=10000",
                    "-c", "pg_stat_statements.track=all",
                    "-c", "track_io_timing=on"
            );

    @Test
    void extensionsLoad() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.runScript(conn, chapterDir(20).resolve("extensions.sql"));
            long cnt = SqlRunner.queryLong(conn,
                "SELECT count(*) FROM pg_extension " +
                "WHERE extname IN ('pg_stat_statements','pg_buffercache')");
            assertEquals(2, cnt, "monitoring extensions loaded");
        }
    }

    @Test
    void seedLoads() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.runScript(conn, chapterDir(20).resolve("extensions.sql"));
            SqlRunner.initAndSeed(conn, chapterDir(20));
            long reviews = SqlRunner.queryLong(conn, "SELECT count(*) FROM reviews");
            assertGte(reviews, 10000, "chapter-20 reviews seeded");
        }
    }

    @Test
    void pgStatStatementsCollectsStats() throws Exception {
        try (Connection conn = connect(PG)) {
            // Install the extension (shared_preload_libraries is already set at server start).
            SqlRunner.runScript(conn, chapterDir(20).resolve("extensions.sql"));
            SqlRunner.initAndSeed(conn, chapterDir(20));

            // Reset counters so only the workload below is captured.
            SqlRunner.runStatements(conn, "SELECT pg_stat_statements_reset()");

            // Run a known workload: home-feed query for follower_id = 1.
            SqlRunner.runStatements(conn,
                "SELECT r.id, r.body, r.posted_at, m.title " +
                "FROM reviews r " +
                "JOIN movies m ON m.id = r.movie_id " +
                "JOIN follows f ON f.followed_id = r.user_id " +
                "WHERE f.follower_id = 1 " +
                "ORDER BY r.posted_at DESC LIMIT 20");

            // pg_stat_statements must have captured the query above.
            // The query text is normalised; match on the FROM clause fragment.
            List<String> rows = SqlRunner.queryColumn(conn,
                "SELECT query FROM pg_stat_statements WHERE query LIKE '%FROM reviews%' LIMIT 10");
            assertThat(!rows.isEmpty(),
                "pg_stat_statements captured the home-feed query; got zero rows");

            // Verify call count is non-zero for that entry.
            long calls = SqlRunner.queryLong(conn,
                "SELECT calls FROM pg_stat_statements WHERE query LIKE '%FROM reviews%' LIMIT 1");
            assertGte(calls, 1, "pg_stat_statements call count for home-feed query");
        }
    }

    @Test
    void slowestQueriesByMeanTime() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.runScript(conn, chapterDir(20).resolve("extensions.sql"));
            SqlRunner.initAndSeed(conn, chapterDir(20));

            // Run a workload so pg_stat_statements has data.
            SqlRunner.runStatements(conn, "SELECT pg_stat_statements_reset()");
            SqlRunner.runStatements(conn,
                "SELECT r.id, r.body, r.posted_at, m.title " +
                "FROM reviews r " +
                "JOIN movies m ON m.id = r.movie_id " +
                "JOIN follows f ON f.followed_id = r.user_id " +
                "WHERE f.follower_id = 1 " +
                "ORDER BY r.posted_at DESC LIMIT 20");

            // Top queries by mean execution time - must return at least one row.
            long topCount = SqlRunner.queryLong(conn,
                "SELECT count(*) FROM pg_stat_statements WHERE mean_exec_time > 0");
            assertGte(topCount, 1, "pg_stat_statements contains queries with non-zero mean_exec_time");
        }
    }

    @Test
    void pgBuffercacheAccessible() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.runScript(conn, chapterDir(20).resolve("extensions.sql"));

            long pages = SqlRunner.queryLong(conn,
                "SELECT count(*) FROM pg_buffercache WHERE reldatabase IS NOT NULL");
            assertGte(pages, 0, "pg_buffercache accessible");
        }
    }

    @Test
    void homeFeedQueryPlanDiagnosis() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.runScript(conn, chapterDir(20).resolve("extensions.sql"));
            SqlRunner.initAndSeed(conn, chapterDir(20));
            SqlRunner.runStatements(conn, "ANALYZE reviews; ANALYZE follows; ANALYZE movies;");

            String plan = SqlRunner.explainAnalyze(conn,
                "SELECT r.id, r.body, r.posted_at, m.title " +
                "FROM reviews r " +
                "JOIN movies m ON m.id = r.movie_id " +
                "JOIN follows f ON f.followed_id = r.user_id " +
                "WHERE f.follower_id = 1 " +
                "ORDER BY r.posted_at DESC LIMIT 20");
            assertThat(plan != null && !plan.isEmpty(), "home-feed EXPLAIN ran");
        }
    }
}
