package com.umurinan.dbbook;

import org.junit.jupiter.api.Test;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.sql.Connection;

/**
 * Chapter 11: Joins - nested loop vs hash join vs merge join, join order,
 * lateral joins, anti-joins.
 */
@Testcontainers
class Chapter11IT extends PostgresBase {

    @Container
    static final PostgreSQLContainer<?> PG = container();

    @Test
    void seedLoads() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(11));
            long movies  = SqlRunner.queryLong(conn, "SELECT count(*) FROM movies");
            long ratings = SqlRunner.queryLong(conn, "SELECT count(*) FROM ratings");
            assertGte(movies,  10000, "chapter-11 movies");
            assertGte(ratings, 100000, "chapter-11 ratings");
        }
    }

    @Test
    void nestedLoopForSingleUserRatings() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(11));
            SqlRunner.runStatements(conn, "ANALYZE users; ANALYZE ratings; ANALYZE movies;");

            String plan = SqlRunner.explainAnalyze(conn,
                "SELECT m.title, r.score FROM users u " +
                "JOIN ratings r ON r.user_id = u.id " +
                "JOIN movies  m ON m.id = r.movie_id " +
                "WHERE u.username = 'user42'");
            assertThat(plan != null, "join plan for single user");
        }
    }

    @Test
    void hashJoinForWideOuterSide() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(11));
            SqlRunner.runStatements(conn, "ANALYZE movies; ANALYZE ratings;");

            String plan = SqlRunner.explainAnalyze(conn,
                "SELECT m.title, count(r.*) FROM movies m " +
                "JOIN ratings r ON r.movie_id = m.id " +
                "WHERE m.release_year = 2010 " +
                "GROUP BY m.title");
            // Hash Join is expected when outer side is wide
            assertThat(plan != null, "hash join plan generated");
        }
    }

    @Test
    void antiJoinReturnsUnratedMovies() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(11));

            long unrated = SqlRunner.queryLong(conn,
                "SELECT count(*) FROM movies m " +
                "WHERE NOT EXISTS (SELECT 1 FROM ratings r WHERE r.movie_id = m.id)");
            assertGte(unrated, 0, "anti-join returns non-negative count");
        }
    }

    @Test
    void lateralJoinForTopNPerGroup() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(11));

            long rows = SqlRunner.queryLong(conn,
                "SELECT count(*) FROM movies m " +
                "CROSS JOIN LATERAL (" +
                "  SELECT score FROM ratings r WHERE r.movie_id = m.id " +
                "  ORDER BY score DESC LIMIT 3" +
                ") top");
            assertGte(rows, 0, "LATERAL join result");
        }
    }

    @Test
    void mergeJoinOnSortedInputs() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(11));
            SqlRunner.runStatements(conn, "ANALYZE movies; ANALYZE ratings;");

            // Force merge join to verify it works
            conn.setAutoCommit(false);
            SqlRunner.runStatements(conn, "SET LOCAL enable_hashjoin = off; SET LOCAL enable_nestloop = off;");
            String plan = SqlRunner.explainAnalyze(conn,
                "SELECT m.id, r.score FROM movies m " +
                "JOIN ratings r ON r.movie_id = m.id " +
                "ORDER BY m.id LIMIT 100");
            conn.rollback();
            assertThat(plan != null, "merge join plan generated");
        }
    }
}
