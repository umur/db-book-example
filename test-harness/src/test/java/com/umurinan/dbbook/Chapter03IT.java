package com.umurinan.dbbook;

import org.junit.jupiter.api.Test;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.sql.Connection;

/**
 * Chapter 3: Storage internals - pageinspect, pgstattuple, TOAST, HOT.
 */
@Testcontainers
class Chapter03IT extends PostgresBase {

    @Container
    static final PostgreSQLContainer<?> PG = container();

    @Test
    void extensionsLoadable() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.runScript(conn, chapterDir(3).resolve("extensions.sql"));
            SqlRunner.initAndSeed(conn, chapterDir(3));

            long extCount = SqlRunner.queryLong(conn,
                "SELECT count(*) FROM pg_extension " +
                "WHERE extname IN ('pageinspect','pgstattuple','pg_freespacemap')");
            assertEquals(3, extCount, "storage extensions loaded");
        }
    }

    @Test
    void pageHeaderQueryRuns() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.runScript(conn, chapterDir(3).resolve("extensions.sql"));
            SqlRunner.initAndSeed(conn, chapterDir(3));

            // page_header on page 0 of reviews
            long pagesize = SqlRunner.queryLong(conn,
                "SELECT pagesize FROM page_header(get_raw_page('reviews',0))");
            assertEquals(8192, pagesize, "page size");
        }
    }

    @Test
    void heapPageItemsQueryRuns() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.runScript(conn, chapterDir(3).resolve("extensions.sql"));
            SqlRunner.initAndSeed(conn, chapterDir(3));

            long items = SqlRunner.queryLong(conn,
                "SELECT count(*) FROM heap_page_items(get_raw_page('reviews',0))");
            assertGte(items, 1, "heap page items on page 0");
        }
    }

    @Test
    void pgstattupleQueryRuns() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.runScript(conn, chapterDir(3).resolve("extensions.sql"));
            SqlRunner.initAndSeed(conn, chapterDir(3));

            // pgstattuple returns live_percent, dead_tuple_percent etc.
            long tuplePct = SqlRunner.queryLong(conn,
                "SELECT (tuple_percent)::int FROM pgstattuple('reviews')");
            assertGte(tuplePct, 0, "tuple percent non-negative");
        }
    }

    @Test
    void toastTableExists() throws Exception {
        try (Connection conn = connect(PG)) {
            SqlRunner.runScript(conn, chapterDir(3).resolve("extensions.sql"));
            SqlRunner.initAndSeed(conn, chapterDir(3));

            // reviews.body is TEXT -> TOAST table should exist
            long toastCount = SqlRunner.queryLong(conn,
                "SELECT count(*) FROM pg_class c " +
                "JOIN pg_class t ON t.oid = c.reltoastrelid " +
                "WHERE c.relname='reviews'");
            assertGte(toastCount, 1, "TOAST table for reviews");
        }
    }
}
