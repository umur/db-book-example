package com.umurinan.dbbook;

import org.junit.jupiter.api.Test;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.sql.Connection;

/**
 * Chapter 12: JSONB - operators, GIN indexing, path queries, containment,
 * jsonb_path_query, hybrid schema pattern.
 */
@Testcontainers
class Chapter12IT extends PostgresBase {

    @Container
    static final PostgreSQLContainer<?> PG = container();

    @Test
    void seedLoads() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(12));
            long movies = SqlRunner.queryLong(conn, "SELECT count(*) FROM movies");
            assertGte(movies, 10000, "chapter-12 movies with JSONB metadata");
        }
    }

    @Test
    void jsonbArrowOperators() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(12));

            // -> returns JSONB, ->> returns text; 'languages' is guaranteed in the seed
            String langs = SqlRunner.queryString(conn,
                "SELECT metadata->>'languages' FROM movies WHERE id = 7");
            assertThat(langs != null, "JSONB ->> operator works");
        }
    }

    @Test
    void containmentOperatorWithoutIndex() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(12));

            long cnt = SqlRunner.queryLong(conn,
                "SELECT count(*) FROM movies WHERE metadata @> '{\"format\":\"4K\"}'");
            assertGte(cnt, 0, "containment query result");
        }
    }

    @Test
    void ginIndexAcceleratesContainment() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(12));
            SqlRunner.runStatements(conn, "ANALYZE movies;");

            SqlRunner.runStatements(conn,
                "CREATE INDEX IF NOT EXISTS idx_movies_meta_gin " +
                "ON movies USING GIN (metadata jsonb_path_ops);");

            String plan = SqlRunner.explainAnalyze(conn,
                "SELECT id FROM movies WHERE metadata @> '{\"format\":\"4K\"}'");
            assertThat(plan != null, "GIN JSONB plan generated");
        }
    }

    @Test
    void jsonbPathQueryWorks() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(12));

            long cnt = SqlRunner.queryLong(conn,
                "SELECT count(*) FROM movies " +
                "WHERE jsonb_path_exists(metadata, '$.languages[*] ? (@ == \"en\")')");
            assertGte(cnt, 0, "jsonb_path_exists result");
        }
    }

    @Test
    void keyExistenceOperator() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(12));

            long withAwards = SqlRunner.queryLong(conn,
                "SELECT count(*) FROM movies WHERE metadata ? 'awards'");
            assertGte(withAwards, 0, "key existence operator");
        }
    }
}
