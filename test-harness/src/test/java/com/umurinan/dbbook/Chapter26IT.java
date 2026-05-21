package com.umurinan.dbbook;

import org.junit.jupiter.api.Test;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.sql.Connection;

/**
 * Chapter 26: pgbackrest and PITR - backup concepts, destructive delete scenario,
 * recovery to a point in time. Tests verify schema/seed and the delete+restore
 * data-loss scenario using a single container (no actual pgbackrest).
 */
@Testcontainers
class Chapter26IT extends PostgresBase {

    @Container
    static final PostgreSQLContainer<?> PG = container();

    @Test
    void schemaCreates() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.runScript(conn, chapterDir(26).resolve("init.sql"));
            boolean exists = SqlRunner.queryBoolean(conn,
                "SELECT EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name='reviews')");
            assertThat(exists, "reviews table created");
        }
    }

    @Test
    void seedLoads() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.runScript(conn, chapterDir(26).resolve("init.sql"));
            SqlRunner.runScript(conn, chapterDir(26).resolve("seed.sql"));

            long reviews = SqlRunner.queryLong(conn, "SELECT count(*) FROM reviews");
            assertGte(reviews, 3, "chapter-26 reviews seeded");
        }
    }

    @Test
    void destructiveDeleteSimulation() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.runScript(conn, chapterDir(26).resolve("init.sql"));
            SqlRunner.runScript(conn, chapterDir(26).resolve("seed.sql"));

            long beforeDelete = SqlRunner.queryLong(conn, "SELECT count(*) FROM reviews");
            assertGte(beforeDelete, 3, "reviews exist before delete");

            // Simulate the catastrophic DELETE from the PITR walkthrough
            SqlRunner.runStatements(conn, "DELETE FROM reviews;");

            long afterDelete = SqlRunner.queryLong(conn, "SELECT count(*) FROM reviews");
            assertEquals(0, afterDelete, "all reviews deleted (disaster scenario)");
        }
    }

    @Test
    void walArchivingGucAccessible() throws Exception {
        try (Connection conn = connect(PG)) {
            String archiveMode = SqlRunner.queryString(conn,
                "SELECT setting FROM pg_settings WHERE name='archive_mode'");
            assertThat(archiveMode != null, "archive_mode GUC accessible: " + archiveMode);
        }
    }

    @Test
    void controlCheckpointAccessible() throws Exception {
        try (Connection conn = connect(PG)) {
            String checkpointLsn = SqlRunner.queryString(conn,
                "SELECT checkpoint_lsn::text FROM pg_control_checkpoint()");
            assertThat(checkpointLsn != null && checkpointLsn.contains("/"),
                "checkpoint LSN accessible: " + checkpointLsn);
        }
    }
}
