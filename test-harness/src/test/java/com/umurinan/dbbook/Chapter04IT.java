package com.umurinan.dbbook;

import org.junit.jupiter.api.Test;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.sql.Connection;

/**
 * Chapter 4: WAL - LSN tracking, WAL volume measurement, checkpoint behavior.
 */
@Testcontainers
class Chapter04IT extends PostgresBase {

    @Container
    static final PostgreSQLContainer<?> PG = container();

    @Test
    void schemaAndSeedLoad() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(4));
            long movies = SqlRunner.queryLong(conn, "SELECT count(*) FROM movies");
            assertGte(movies, 10, "movies seeded");
        }
    }

    @Test
    void currentWalLsnAccessible() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(4));
            String lsn = SqlRunner.queryString(conn, "SELECT pg_current_wal_lsn()::text");
            assertThat(lsn != null && lsn.contains("/"), "LSN format: " + lsn);
        }
    }

    @Test
    void walVolumeIncreasesAfterInserts() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(4));

            long lsnBefore = SqlRunner.queryLong(conn,
                "SELECT pg_current_wal_lsn() - '0/0'::pg_lsn");

            SqlRunner.runStatements(conn,
                "INSERT INTO reviews (user_id, movie_id, body) " +
                "SELECT ((g-1)%25)+1, ((g*7)%50)+1, 'WAL test ' || g " +
                "FROM generate_series(1,500) AS g;");

            long lsnAfter = SqlRunner.queryLong(conn,
                "SELECT pg_current_wal_lsn() - '0/0'::pg_lsn");

            assertGt(lsnAfter, lsnBefore, "WAL LSN advanced after inserts");
        }
    }

    @Test
    void walFileNameFunctionRuns() throws Exception {
        try (Connection conn = connect(PG)) {
            String walFile = SqlRunner.queryString(conn,
                "SELECT pg_walfile_name(pg_current_wal_lsn())");
            assertThat(walFile != null && walFile.length() > 0, "WAL file name: " + walFile);
        }
    }

    @Test
    void walLevelIsAtLeastReplica() throws Exception {
        try (Connection conn = connect(PG)) {
            String level = SqlRunner.queryString(conn,
                "SELECT setting FROM pg_settings WHERE name='wal_level'");
            assertThat(
                "replica".equals(level) || "logical".equals(level),
                "wal_level is replica or logical, got: " + level);
        }
    }
}
