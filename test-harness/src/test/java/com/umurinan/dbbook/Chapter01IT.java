package com.umurinan.dbbook;

import org.junit.jupiter.api.Test;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.sql.Connection;

/**
 * Chapter 1: Starter schema, MVCC peek, first EXPLAIN, catalog browse.
 * Verifies: schema created, seed counts, EXPLAIN runs, system columns accessible.
 */
@Testcontainers
class Chapter01IT extends PostgresBase {

    @Container
    static final PostgreSQLContainer<?> PG = container();

    @Test
    void schemaAndSeedLoaded() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(1));

            long movies = SqlRunner.queryLong(conn, "SELECT count(*) FROM movies");
            long users  = SqlRunner.queryLong(conn, "SELECT count(*) FROM users");
            long ratings = SqlRunner.queryLong(conn, "SELECT count(*) FROM ratings");
            long reviews = SqlRunner.queryLong(conn, "SELECT count(*) FROM reviews");

            assertGte(movies,  100, "movies count");
            assertGte(users,    50, "users count");
            assertGte(ratings,  50, "ratings count");
            assertGte(reviews,  50, "reviews count");
        }
    }

    @Test
    void systemColumnsAccessible() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(1));
            // xmin, xmax, ctid are system columns - access via tableoid trick
            long rows = SqlRunner.queryLong(conn,
                "SELECT count(*) FROM (SELECT xmin, xmax, ctid, id FROM reviews LIMIT 5) t");
            assertGte(rows, 1, "system columns rows");
        }
    }

    @Test
    void explainRunsWithoutError() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(1));
            String plan = SqlRunner.explainAnalyze(conn,
                "SELECT m.id, m.title, count(r.*) AS num_ratings " +
                "FROM movies m JOIN ratings r ON r.movie_id = m.id " +
                "WHERE m.release_year >= 1995 " +
                "GROUP BY m.id HAVING count(r.*) >= 1 " +
                "ORDER BY num_ratings DESC LIMIT 10");
            assertThat(plan != null && !plan.isEmpty(), "EXPLAIN output not empty");
        }
    }

    @Test
    void tableSizeQueryRuns() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(1));
            long tables = SqlRunner.queryLong(conn,
                "SELECT count(*) FROM pg_class c " +
                "JOIN pg_namespace n ON n.oid = c.relnamespace " +
                "WHERE n.nspname = 'public' AND c.relkind = 'r'");
            assertGte(tables, 5, "public table count");
        }
    }

    @Test
    void indexesExist() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(1));
            long idxCount = SqlRunner.queryLong(conn,
                "SELECT count(*) FROM pg_indexes WHERE schemaname='public' AND indexname LIKE 'idx_%'");
            assertGte(idxCount, 3, "named indexes");
        }
    }
}
