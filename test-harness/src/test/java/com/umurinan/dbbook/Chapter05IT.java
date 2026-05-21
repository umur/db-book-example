package com.umurinan.dbbook;

import org.junit.jupiter.api.Test;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.sql.Connection;

/**
 * Chapter 5: Memory - shared_buffers, work_mem, sort spills, temp files.
 */
@Testcontainers
class Chapter05IT extends PostgresBase {

    @Container
    static final PostgreSQLContainer<?> PG = container();

    @Test
    void memorySettingsAccessible() throws Exception {
        try (Connection conn = connect(PG)) {
            String sharedBuffers = SqlRunner.queryString(conn,
                "SELECT setting FROM pg_settings WHERE name='shared_buffers'");
            String workMem = SqlRunner.queryString(conn,
                "SELECT setting FROM pg_settings WHERE name='work_mem'");
            assertThat(sharedBuffers != null, "shared_buffers accessible");
            assertThat(workMem != null, "work_mem accessible");
        }
    }

    @Test
    void seedLoadsLargeViewEvents() throws Exception {
        try (Connection conn = connect(PG)) {
            // Chapter 5 has a large seed; just init + seed and verify > 1000 view_events
            SqlRunner.initAndSeed(conn, chapterDir(5));
            long ve = SqlRunner.queryLong(conn, "SELECT count(*) FROM view_events");
            assertGte(ve, 1000, "view_events seeded");
        }
    }

    @Test
    void workMemGucIsConfigurable() throws Exception {
        try (Connection conn = connect(PG)) {
            conn.setAutoCommit(false);
            SqlRunner.runStatements(conn, "SET LOCAL work_mem = '4MB';");
            String wm = SqlRunner.queryString(conn, "SHOW work_mem;");
            conn.rollback();
            assertThat(wm != null && wm.contains("4MB"), "work_mem set to 4MB: " + wm);
        }
    }

    @Test
    void sortQueryRunsUnderLowWorkMem() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(5));
            conn.setAutoCommit(false);
            SqlRunner.runStatements(conn, "SET LOCAL work_mem = '64kB';");
            // Should complete without error even with tiny work_mem (may spill to disk)
            long rows = SqlRunner.queryLong(conn,
                "SELECT count(*) FROM (" +
                "  SELECT user_id, occurred_at FROM view_events ORDER BY occurred_at LIMIT 1000" +
                ") t");
            conn.rollback();
            assertEquals(1000, rows, "sorted result count");
        }
    }

    @Test
    void effectiveCacheSizeAccessible() throws Exception {
        try (Connection conn = connect(PG)) {
            String ecs = SqlRunner.queryString(conn,
                "SELECT setting FROM pg_settings WHERE name='effective_cache_size'");
            assertThat(ecs != null, "effective_cache_size accessible");
        }
    }
}
