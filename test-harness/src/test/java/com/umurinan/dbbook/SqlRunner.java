package com.umurinan.dbbook;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.List;

/**
 * Utility methods for running SQL scripts and querying results in tests.
 * No Mockito. No framework dependencies beyond JDBC.
 */
public final class SqlRunner {

    private SqlRunner() {}

    /**
     * Execute a SQL file against the given connection.
     * Handles dollar-quoted blocks (DO $$ ... $$), single-quoted strings,
     * and psql meta-commands (stripped).
     */
    public static void runScript(Connection conn, Path sqlFile) throws IOException, SQLException {
        String content = Files.readString(sqlFile);
        runStatements(conn, content);
    }

    /**
     * Split SQL text into individual statements respecting:
     * - Dollar-quoting: $tag$...$tag$ (including bare $$...$$)
     * - Single-quoted string literals
     * - Single-line (--) and block (/* *\/) comments
     * - psql backslash meta-commands (stripped)
     * Statements are split on semicolons that appear outside any quote/comment context.
     */
    public static void runStatements(Connection conn, String sql) throws SQLException {
        List<String> statements = splitStatements(sql);
        try (Statement st = conn.createStatement()) {
            for (String stmt : statements) {
                String trimmed = stmt.strip();
                if (trimmed.isEmpty()) continue;
                try {
                    st.execute(trimmed);
                } catch (SQLException e) {
                    String msg = e.getMessage();
                    // Skip harmless DDL errors
                    if (msg != null && (
                            msg.contains("already exists")
                            || msg.contains("does not exist")
                            || msg.contains("duplicate key")
                            || msg.contains("cannot be run inside a transaction")
                    )) {
                        continue;
                    }
                    throw new SQLException(
                        "Error in statement: ["
                        + trimmed.substring(0, Math.min(120, trimmed.length()))
                        + "] -> " + msg, e);
                }
            }
        }
    }

    /**
     * Proper SQL statement splitter that understands:
     * - single-quoted strings  'it''s fine'
     * - dollar-quoted blocks   $$ ... $$ or $tag$ ... $tag$
     * - single-line comments   -- ...
     * - block comments         /* ... *\/
     * - psql meta-commands     \command (stripped entirely)
     */
    static List<String> splitStatements(String sql) {
        List<String> result = new ArrayList<>();
        StringBuilder current = new StringBuilder();
        int i = 0;
        int len = sql.length();

        while (i < len) {
            char c = sql.charAt(i);

            // psql backslash meta-commands: skip entire line
            if (c == '\\' && (i == 0 || sql.charAt(i - 1) == '\n' || isLineStart(sql, i))) {
                while (i < len && sql.charAt(i) != '\n') i++;
                continue;
            }

            // Single-line comment: -- ... \n
            if (c == '-' && i + 1 < len && sql.charAt(i + 1) == '-') {
                while (i < len && sql.charAt(i) != '\n') i++;
                current.append('\n');
                continue;
            }

            // Block comment: /* ... */
            if (c == '/' && i + 1 < len && sql.charAt(i + 1) == '*') {
                i += 2;
                while (i + 1 < len && !(sql.charAt(i) == '*' && sql.charAt(i + 1) == '/')) {
                    i++;
                }
                i += 2; // skip */
                current.append(' ');
                continue;
            }

            // Dollar-quoted string: $$...$$ or $tag$...$tag$
            if (c == '$') {
                int tagEnd = sql.indexOf('$', i + 1);
                if (tagEnd >= i + 1) {
                    String tag = sql.substring(i, tagEnd + 1); // e.g. "$tag$" or "$$"
                    // Check tag contains only identifier chars (or is bare $$)
                    boolean validTag = true;
                    for (int t = 1; t < tag.length() - 1; t++) {
                        char tc = tag.charAt(t);
                        if (!Character.isLetterOrDigit(tc) && tc != '_') {
                            validTag = false;
                            break;
                        }
                    }
                    if (validTag) {
                        int closeIdx = sql.indexOf(tag, tagEnd + 1);
                        if (closeIdx >= 0) {
                            // Append entire dollar-quoted block including delimiters
                            String block = sql.substring(i, closeIdx + tag.length());
                            current.append(block);
                            i = closeIdx + tag.length();
                            continue;
                        }
                    }
                }
            }

            // Single-quoted string: '...' with '' escapes
            if (c == '\'') {
                current.append(c);
                i++;
                while (i < len) {
                    char sc = sql.charAt(i);
                    current.append(sc);
                    i++;
                    if (sc == '\'') {
                        // Check for escaped quote ''
                        if (i < len && sql.charAt(i) == '\'') {
                            current.append('\'');
                            i++;
                        } else {
                            break;
                        }
                    }
                }
                continue;
            }

            // Statement terminator
            if (c == ';') {
                String stmt = current.toString().strip();
                if (!stmt.isEmpty()) {
                    result.add(stmt);
                }
                current.setLength(0);
                i++;
                continue;
            }

            current.append(c);
            i++;
        }

        // Trailing statement without semicolon
        String trailing = current.toString().strip();
        if (!trailing.isEmpty()) {
            result.add(trailing);
        }

        return result;
    }

    private static boolean isLineStart(String sql, int i) {
        for (int j = i - 1; j >= 0; j--) {
            char c = sql.charAt(j);
            if (c == '\n') return true;
            if (c != ' ' && c != '\t') return false;
        }
        return true;
    }

    /** Execute SQL scripts in order: init.sql, then seed.sql. */
    public static void initAndSeed(Connection conn, Path chapterDir) throws IOException, SQLException {
        Path init = chapterDir.resolve("init.sql");
        Path seed = chapterDir.resolve("seed.sql");
        if (Files.exists(init)) runScript(conn, init);
        if (Files.exists(seed)) runScript(conn, seed);
    }

    /** Return a single long from a SELECT COUNT(*) or similar query. */
    public static long queryLong(Connection conn, String sql) throws SQLException {
        try (Statement st = conn.createStatement();
             ResultSet rs = st.executeQuery(sql)) {
            if (rs.next()) return rs.getLong(1);
            return 0L;
        }
    }

    public static String queryString(Connection conn, String sql) throws SQLException {
        try (Statement st = conn.createStatement();
             ResultSet rs = st.executeQuery(sql)) {
            if (rs.next()) return rs.getString(1);
            return null;
        }
    }

    public static boolean queryBoolean(Connection conn, String sql) throws SQLException {
        try (Statement st = conn.createStatement();
             ResultSet rs = st.executeQuery(sql)) {
            if (rs.next()) return rs.getBoolean(1);
            return false;
        }
    }

    public static List<String> queryColumn(Connection conn, String sql) throws SQLException {
        List<String> result = new ArrayList<>();
        try (Statement st = conn.createStatement();
             ResultSet rs = st.executeQuery(sql)) {
            while (rs.next()) result.add(rs.getString(1));
        }
        return result;
    }

    /** Run EXPLAIN ANALYZE and return the full plan text. */
    public static String explainAnalyze(Connection conn, String query) throws SQLException {
        StringBuilder sb = new StringBuilder();
        try (Statement st = conn.createStatement();
             ResultSet rs = st.executeQuery("EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) " + query)) {
            while (rs.next()) sb.append(rs.getString(1)).append("\n");
        }
        return sb.toString();
    }
}
