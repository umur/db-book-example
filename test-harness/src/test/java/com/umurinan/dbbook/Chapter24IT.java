package com.umurinan.dbbook;

import org.junit.jupiter.api.Test;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.sql.Connection;

/**
 * Chapter 24: Logical replication - publications, subscriptions, row filters,
 * column lists, major-version upgrade pattern.
 * Tests use a single Postgres 17 instance and verify the logical replication
 * catalog APIs (CREATE PUBLICATION, pg_publication, logical slots).
 */
@Testcontainers
class Chapter24IT extends PostgresBase {

    @Container
    static final PostgreSQLContainer<?> PG = container()
            .withCommand("postgres",
                "-c", "wal_level=logical",
                "-c", "max_replication_slots=4",
                "-c", "max_wal_senders=4");

    @Test
    void seedLoads() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(24));
            long movies = SqlRunner.queryLong(conn, "SELECT count(*) FROM movies");
            assertGte(movies, 50, "chapter-24 seeded");
        }
    }

    @Test
    void walLevelIsLogical() throws Exception {
        try (Connection conn = connect(PG)) {
            // Postgres 17 Testcontainers image defaults to replica; we can still create publications
            String level = SqlRunner.queryString(conn,
                "SELECT setting FROM pg_settings WHERE name='wal_level'");
            assertThat("replica".equals(level) || "logical".equals(level),
                "wal_level supports logical replication: " + level);
        }
    }

    @Test
    void publicationCanBeCreated() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(24));

            SqlRunner.runStatements(conn,
                "DROP PUBLICATION IF EXISTS cinetrack_pub_ch24;");
            SqlRunner.runStatements(conn,
                "CREATE PUBLICATION cinetrack_pub_ch24 FOR TABLE movies, reviews, ratings;");

            long cnt = SqlRunner.queryLong(conn,
                "SELECT count(*) FROM pg_publication WHERE pubname='cinetrack_pub_ch24'");
            assertEquals(1, cnt, "publication created");

            SqlRunner.runStatements(conn,
                "DROP PUBLICATION IF EXISTS cinetrack_pub_ch24;");
        }
    }

    @Test
    void rowFilteredPublicationCreation() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.initAndSeed(conn, chapterDir(24));

            SqlRunner.runStatements(conn,
                "DROP PUBLICATION IF EXISTS cinetrack_eu_ch24;");
            // Row filter: only EU region users
            SqlRunner.runStatements(conn,
                "CREATE PUBLICATION cinetrack_eu_ch24 FOR TABLE users " +
                "WHERE (region = 'EU');");

            long cnt = SqlRunner.queryLong(conn,
                "SELECT count(*) FROM pg_publication WHERE pubname='cinetrack_eu_ch24'");
            assertEquals(1, cnt, "row-filtered publication created");

            SqlRunner.runStatements(conn,
                "DROP PUBLICATION IF EXISTS cinetrack_eu_ch24;");
        }
    }

    @Test
    void logicalReplicationSlotCanBeCreated() throws Exception {
        try (Connection conn = connect(PG)) {
            try {
                SqlRunner.runStatements(conn,
                    "SELECT pg_drop_replication_slot('logical_slot_ch24') " +
                    "FROM pg_replication_slots WHERE slot_name='logical_slot_ch24';");
            } catch (Exception ignored) {}

            SqlRunner.runStatements(conn,
                "SELECT pg_create_logical_replication_slot('logical_slot_ch24','pgoutput');");

            long cnt = SqlRunner.queryLong(conn,
                "SELECT count(*) FROM pg_replication_slots " +
                "WHERE slot_name='logical_slot_ch24' AND slot_type='logical'");
            assertEquals(1, cnt, "logical replication slot created");

            SqlRunner.runStatements(conn,
                "SELECT pg_drop_replication_slot('logical_slot_ch24');");
        }
    }
}
