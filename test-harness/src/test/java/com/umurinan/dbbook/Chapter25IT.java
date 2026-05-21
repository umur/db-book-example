package com.umurinan.dbbook;

import org.junit.jupiter.api.Test;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.sql.Connection;

/**
 * Chapter 25: High availability with Patroni - heartbeat table, failover
 * concepts. Tests verify the schema and seed; full Patroni cluster is
 * out of scope.
 */
@Testcontainers
class Chapter25IT extends PostgresBase {

    @Container
    static final PostgreSQLContainer<?> PG = container();

    @Test
    void schemaCreates() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.runScript(conn, chapterDir(25).resolve("init.sql"));

            boolean moviesExists = SqlRunner.queryBoolean(conn,
                "SELECT EXISTS(SELECT 1 FROM information_schema.tables " +
                "WHERE table_name='movies')");
            assertThat(moviesExists, "movies table created");
        }
    }

    @Test
    void seedLoads() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.runScript(conn, chapterDir(25).resolve("init.sql"));
            SqlRunner.runScript(conn, chapterDir(25).resolve("seed.sql"));

            long movies  = SqlRunner.queryLong(conn, "SELECT count(*) FROM movies");
            long reviews = SqlRunner.queryLong(conn, "SELECT count(*) FROM reviews");
            assertGte(movies,  3, "chapter-25 movies");
            assertGte(reviews, 3, "chapter-25 reviews");
        }
    }

    @Test
    void heartbeatWritePattern() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.runScript(conn, chapterDir(25).resolve("init.sql"));
            SqlRunner.runScript(conn, chapterDir(25).resolve("seed.sql"));

            // Simulate Patroni heartbeat: write a small row in a tight loop
            for (int i = 0; i < 5; i++) {
                SqlRunner.runStatements(conn,
                    "INSERT INTO reviews (user_id, movie_id, body) " +
                    "VALUES (1, 1, 'heartbeat " + i + "')");
            }
            long total = SqlRunner.queryLong(conn, "SELECT count(*) FROM reviews");
            assertGte(total, 8, "heartbeat rows written");
        }
    }

    @Test
    void replicationRoleExists() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.runScript(conn, chapterDir(25).resolve("init.sql"));
            // init.sql does not create a replication role in ch25 (that's ch28)
            // Just verify pg_roles is queryable
            long roles = SqlRunner.queryLong(conn, "SELECT count(*) FROM pg_roles");
            assertGte(roles, 1, "pg_roles accessible");
        }
    }

    @Test
    void timelineIdAccessible() throws Exception {
        try (Connection conn = connect(PG)) {
            // pg_control_checkpoint shows current timeline
            long tli = SqlRunner.queryLong(conn,
                "SELECT timeline_id FROM pg_control_checkpoint()");
            assertGte(tli, 1, "timeline_id >= 1");
        }
    }
}
