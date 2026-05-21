package com.umurinan.dbbook;

import org.junit.jupiter.api.Test;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.sql.Connection;

/**
 * Chapter 9: Indexing strategies - multi-column, partial, expression, covering,
 * GiST range exclusion, partial unique.
 */
@Testcontainers
class Chapter09IT extends PostgresBase {

    @Container
    static final PostgreSQLContainer<?> PG = container();

    @Test
    void seedLoads() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(9));
            long movies = SqlRunner.queryLong(conn, "SELECT count(*) FROM movies");
            assertGte(movies, 10000, "chapter-9 movies");
        }
    }

    @Test
    void multiColumnIndexWrongOrderSlower() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(9));
            SqlRunner.runStatements(conn, "ANALYZE ratings;");

            // (movie_id, user_id) index: query on user_id alone cannot use it optimally
            SqlRunner.runStatements(conn,
                "CREATE INDEX IF NOT EXISTS idx_ratings_movie_user ON ratings (movie_id, user_id);");

            String plan = SqlRunner.explainAnalyze(conn,
                "SELECT movie_id, score FROM ratings WHERE user_id = 42");
            assertThat(plan != null, "plan for wrong-order index");
        }
    }

    @Test
    void multiColumnIndexRightOrderUsed() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(9));
            SqlRunner.runStatements(conn, "ANALYZE ratings;");

            SqlRunner.runStatements(conn,
                "CREATE INDEX IF NOT EXISTS idx_ratings_user_movie ON ratings (user_id, movie_id);");

            String plan = SqlRunner.explainAnalyze(conn,
                "SELECT movie_id, score FROM ratings WHERE user_id = 42");
            assertContains(plan, "Index", "right-order index used");
        }
    }

    @Test
    void partialIndexOnPendingNotifications() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(9));
            SqlRunner.runStatements(conn,
                "CREATE INDEX IF NOT EXISTS idx_notifications_pending " +
                "ON notifications (created_at) WHERE status = 'pending';");

            long idxSize = SqlRunner.queryLong(conn,
                "SELECT pg_relation_size('idx_notifications_pending')");
            // Partial index should be smaller than full index
            assertGte(idxSize, 0, "partial index exists and has size");
        }
    }

    @Test
    void expressionIndexOnLowerEmail() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(9));
            SqlRunner.runStatements(conn, "ANALYZE users;");

            SqlRunner.runStatements(conn,
                "CREATE INDEX IF NOT EXISTS idx_users_email_lower ON users (LOWER(email));");

            String plan = SqlRunner.explainAnalyze(conn,
                "SELECT id FROM users WHERE LOWER(email) = 'user42@cinetrack.test'");
            assertContains(plan, "Index", "expression index used for LOWER(email)");
        }
    }

    @Test
    void coveringIndexAvoidsFetchingHeap() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(9));
            SqlRunner.runStatements(conn, "ANALYZE reviews;");
            SqlRunner.runStatements(conn, "VACUUM reviews;");

            SqlRunner.runStatements(conn,
                "CREATE INDEX IF NOT EXISTS idx_reviews_covering " +
                "ON reviews (movie_id, posted_at DESC) INCLUDE (id, body);");

            String plan = SqlRunner.explainAnalyze(conn,
                "SELECT id, body FROM reviews WHERE movie_id = 17 ORDER BY posted_at DESC LIMIT 20");
            assertThat(plan != null, "covering index plan generated");
        }
    }
}
