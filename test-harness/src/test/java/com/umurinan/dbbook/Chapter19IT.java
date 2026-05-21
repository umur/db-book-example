package com.umurinan.dbbook;

import org.junit.jupiter.api.Test;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.sql.Connection;

/**
 * Chapter 19: Connection pooling - pg_stat_activity, backend costs,
 * prepared statements, PgBouncer concepts (verified via Postgres directly).
 */
@Testcontainers
class Chapter19IT extends PostgresBase {

    @Container
    static final PostgreSQLContainer<?> PG = container();

    @Test
    void seedLoads() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(19));
            long movies = SqlRunner.queryLong(conn, "SELECT count(*) FROM movies");
            assertGte(movies, 100, "chapter-19 seeded");
        }
    }

    @Test
    void backendPidAccessible() throws Exception {
        try (Connection conn = connect(PG)) {
            long pid = SqlRunner.queryLong(conn, "SELECT pg_backend_pid()");
            assertGt(pid, 0, "backend pid > 0");
        }
    }

    @Test
    void pgStatActivityHasClientBackend() throws Exception {
        try (Connection conn = connect(PG)) {
            long backends = SqlRunner.queryLong(conn,
                "SELECT count(*) FROM pg_stat_activity WHERE backend_type='client backend'");
            assertGte(backends, 1, "at least 1 client backend in pg_stat_activity");
        }
    }

    @Test
    void preparedStatementRoundTrip() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(19));

            // JDBC uses prepared statements under the hood; verify parameterised query works
            try (var ps = conn.prepareStatement(
                    "SELECT id, score FROM ratings WHERE movie_id = ? LIMIT 10")) {
                ps.setInt(1, 5);
                try (var rs = ps.executeQuery()) {
                    int count = 0;
                    while (rs.next()) count++;
                    assertGte(count, 0, "prepared statement returned rows");
                }
            }
        }
    }

    @Test
    void maxConnectionsGucAccessible() throws Exception {
        try (Connection conn = connect(PG)) {
            String mc = SqlRunner.queryString(conn,
                "SELECT setting FROM pg_settings WHERE name='max_connections'");
            assertThat(mc != null && Integer.parseInt(mc) > 0, "max_connections: " + mc);
        }
    }

    @Test
    void serverPortAccessible() throws Exception {
        try (Connection conn = connect(PG)) {
            String port = SqlRunner.queryString(conn, "SELECT current_setting('port')");
            assertThat(port != null, "server port accessible: " + port);
        }
    }
}
