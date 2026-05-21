package com.umurinan.dbbook;

import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.utility.TestcontainersConfiguration;

import java.nio.file.Path;
import java.nio.file.Paths;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;

/**
 * Shared helpers for chapter IT classes.
 * Each chapter test spins up its own container (fresh DB per chapter).
 */
public abstract class PostgresBase {

    protected static final String IMAGE = "postgres:17";

    static {
        // On macOS with Docker Desktop the daemon socket lives at a non-standard path.
        // If DOCKER_HOST is not already set in the environment, point Testcontainers
        // at the Docker Desktop socket directly so it does not fall back to
        // docker-cli.sock (which returns 400 and breaks strategy detection).
        String dockerHost = System.getenv("DOCKER_HOST");
        if (dockerHost == null || dockerHost.isEmpty()) {
            // On macOS Docker Desktop, use the raw daemon socket.
            // The CLI proxy at ~/.docker/run/docker.sock rejects versioned API calls
            // below 1.40 with HTTP 400, which breaks Testcontainers negotiation.
            String rawSock = "/Users/" + System.getProperty("user.name")
                + "/Library/Containers/com.docker.docker/Data/docker.raw.sock";
            java.io.File sock = new java.io.File(rawSock);
            if (sock.exists()) {
                System.setProperty("DOCKER_HOST", "unix://" + rawSock);
                // docker.raw.sock requires API >= 1.40; pin docker-java to 1.44
                System.setProperty("docker.io.version", "1.44");
                org.testcontainers.utility.TestcontainersConfiguration.getInstance()
                    .updateUserConfig("docker.host", "unix://" + rawSock);
            }
        }
    }

    /** Base directory of the db-example repo (one level above test-harness). */
    protected static Path chaptersDir() {
        String prop = System.getProperty("chapters.dir");
        if (prop != null) return Paths.get(prop).toAbsolutePath().normalize();
        // Fallback: navigate from test-harness module root
        return Paths.get("..").toAbsolutePath().normalize();
    }

    protected static Path chapterDir(int chapter) {
        return chaptersDir().resolve(String.format("chapter-%02d", chapter));
    }

    protected static PostgreSQLContainer<?> container(String initScriptClasspath) {
        PostgreSQLContainer<?> pg = new PostgreSQLContainer<>(IMAGE)
                .withDatabaseName("cinetrack")
                .withUsername("cinetrack")
                .withPassword("cinetrack");
        if (initScriptClasspath != null) {
            pg = pg.withInitScript(initScriptClasspath);
        }
        return pg;
    }

    protected static PostgreSQLContainer<?> container() {
        return container(null);
    }

    protected static Connection connect(PostgreSQLContainer<?> pg) throws SQLException {
        return DriverManager.getConnection(pg.getJdbcUrl(), pg.getUsername(), pg.getPassword());
    }

    /** Assert with a descriptive message. */
    protected static void assertThat(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    protected static void assertGt(long actual, long threshold, String label) {
        if (actual <= threshold)
            throw new AssertionError(label + ": expected > " + threshold + " but got " + actual);
    }

    protected static void assertGte(long actual, long threshold, String label) {
        if (actual < threshold)
            throw new AssertionError(label + ": expected >= " + threshold + " but got " + actual);
    }

    protected static void assertEquals(long expected, long actual, String label) {
        if (expected != actual)
            throw new AssertionError(label + ": expected " + expected + " but got " + actual);
    }

    protected static void assertContains(String haystack, String needle, String label) {
        if (haystack == null || !haystack.contains(needle))
            throw new AssertionError(label + ": expected to contain [" + needle + "] in:\n" + haystack);
    }

    protected static void assertNotContains(String haystack, String needle, String label) {
        if (haystack != null && haystack.contains(needle))
            throw new AssertionError(label + ": expected NOT to contain [" + needle + "] in:\n" + haystack);
    }
}
