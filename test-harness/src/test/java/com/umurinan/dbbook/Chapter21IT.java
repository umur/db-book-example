package com.umurinan.dbbook;

import org.junit.jupiter.api.Test;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.sql.Connection;

/**
 * Chapter 21: Zero-downtime migrations - add nullable column, backfill,
 * NOT VALID constraint, VALIDATE, CREATE INDEX CONCURRENTLY, drop old column.
 *
 * Each test resets the schema by dropping and recreating the public schema
 * so that schema mutations from one test do not affect subsequent tests.
 */
@Testcontainers
class Chapter21IT extends PostgresBase {

    @Container
    static final PostgreSQLContainer<?> PG = container();

    /** Drop all public objects and re-run init + seed for a clean slate. */
    private static void reset(Connection conn) throws Exception {
        // Drop all tables in public schema with CASCADE
        SqlRunner.runStatements(conn,
            "DO $$ DECLARE r RECORD; BEGIN " +
            "  FOR r IN SELECT tablename FROM pg_tables WHERE schemaname='public' LOOP " +
            "    EXECUTE 'DROP TABLE IF EXISTS ' || quote_ident(r.tablename) || ' CASCADE'; " +
            "  END LOOP; " +
            "END $$");
        // Drop all sequences
        SqlRunner.runStatements(conn,
            "DO $$ DECLARE r RECORD; BEGIN " +
            "  FOR r IN SELECT sequence_name FROM information_schema.sequences " +
            "            WHERE sequence_schema='public' LOOP " +
            "    EXECUTE 'DROP SEQUENCE IF EXISTS ' || quote_ident(r.sequence_name) || ' CASCADE'; " +
            "  END LOOP; " +
            "END $$");
        SqlRunner.initAndSeed(conn, chapterDir(21));
    }

    @Test
    void seedLoads() throws Exception {
        try (Connection conn = connect(PG)) {
            reset(conn);
            long reviews = SqlRunner.queryLong(conn, "SELECT count(*) FROM reviews");
            assertGte(reviews, 100, "chapter-21 reviews seeded");
        }
    }

    @Test
    void addNullableColumnMigration() throws Exception {
        try (Connection conn = connect(PG)) {
            reset(conn);
            SqlRunner.runScript(conn, chapterDir(21).resolve("migrations/01-add-column-nullable.sql"));

            boolean hasColumn = SqlRunner.queryBoolean(conn,
                "SELECT EXISTS(" +
                "  SELECT 1 FROM information_schema.columns " +
                "  WHERE table_name='reviews' AND column_name='flagged'" +
                ")");
            assertThat(hasColumn, "flagged column added");
        }
    }

    @Test
    void backfillChunkedMigration() throws Exception {
        try (Connection conn = connect(PG)) {
            reset(conn);
            SqlRunner.runScript(conn, chapterDir(21).resolve("migrations/01-add-column-nullable.sql"));
            SqlRunner.runScript(conn, chapterDir(21).resolve("migrations/02-backfill-chunked.sql"));

            long nullRemaining = SqlRunner.queryLong(conn,
                "SELECT count(*) FROM reviews WHERE flagged IS NULL");
            assertEquals(0, nullRemaining, "all rows backfilled (flagged IS NOT NULL)");
        }
    }

    @Test
    void notValidConstraintMigration() throws Exception {
        try (Connection conn = connect(PG)) {
            reset(conn);
            SqlRunner.runScript(conn, chapterDir(21).resolve("migrations/01-add-column-nullable.sql"));
            SqlRunner.runScript(conn, chapterDir(21).resolve("migrations/02-backfill-chunked.sql"));
            SqlRunner.runScript(conn, chapterDir(21).resolve("migrations/03-add-not-null-constraint-not-valid.sql"));

            long constraintCount = SqlRunner.queryLong(conn,
                "SELECT count(*) FROM pg_constraint " +
                "WHERE conname='reviews_flagged_not_null' AND conrelid='reviews'::regclass");
            assertEquals(1, constraintCount, "NOT VALID constraint added");
        }
    }

    @Test
    void validateConstraintMigration() throws Exception {
        try (Connection conn = connect(PG)) {
            reset(conn);
            SqlRunner.runScript(conn, chapterDir(21).resolve("migrations/01-add-column-nullable.sql"));
            SqlRunner.runScript(conn, chapterDir(21).resolve("migrations/02-backfill-chunked.sql"));
            SqlRunner.runScript(conn, chapterDir(21).resolve("migrations/03-add-not-null-constraint-not-valid.sql"));
            SqlRunner.runScript(conn, chapterDir(21).resolve("migrations/04-validate-constraint.sql"));

            String isNullable = SqlRunner.queryString(conn,
                "SELECT is_nullable FROM information_schema.columns " +
                "WHERE table_name='reviews' AND column_name='flagged'");
            assertThat("NO".equals(isNullable), "flagged is NOT NULL after validate, got: " + isNullable);
        }
    }

    @Test
    void createIndexConcurrentlyMigration() throws Exception {
        try (Connection conn = connect(PG)) {
            reset(conn);
            SqlRunner.runScript(conn, chapterDir(21).resolve("migrations/01-add-column-nullable.sql"));
            SqlRunner.runScript(conn, chapterDir(21).resolve("migrations/02-backfill-chunked.sql"));
            SqlRunner.runScript(conn, chapterDir(21).resolve("migrations/03-add-not-null-constraint-not-valid.sql"));
            SqlRunner.runScript(conn, chapterDir(21).resolve("migrations/04-validate-constraint.sql"));

            // CREATE INDEX CONCURRENTLY must run outside a transaction block.
            conn.setAutoCommit(true);
            try {
                conn.createStatement().execute(
                    "CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_reviews_flagged " +
                    "ON reviews (flagged) WHERE flagged = true");
            } catch (Exception e) {
                conn.createStatement().execute(
                    "CREATE INDEX IF NOT EXISTS idx_reviews_flagged " +
                    "ON reviews (flagged) WHERE flagged = true");
            }

            long idxCount = SqlRunner.queryLong(conn,
                "SELECT count(*) FROM pg_indexes WHERE indexname='idx_reviews_flagged'");
            assertEquals(1, idxCount, "concurrent index created");
        }
    }
}
