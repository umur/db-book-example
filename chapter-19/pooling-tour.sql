-- Chapter 19 pooling tour.
-- Run sections (1) and (2) against direct Postgres at port 5432.
-- Run sections (3)+ against pgbouncer at port 6432.
-- Each numbered section maps to a moment in the chapter prose.

-- (1) Direct connection: who am I talking to?
--     Run with:  psql -h localhost -p 5432 -U cinetrack -d cinetrack
--     The pid is a real Postgres backend that lives until you disconnect.
SELECT current_setting('port')                 AS server_port,
       pg_backend_pid()                        AS backend_pid,
       inet_server_addr()                      AS server_addr,
       current_setting('application_name')     AS application_name;

-- (2) Direct connection: see the per-backend cost.
--     Each row is one OS process Postgres has forked.
SELECT pid, backend_type, state, application_name,
       now() - backend_start AS lifetime
FROM pg_stat_activity
WHERE backend_type = 'client backend'
ORDER BY backend_start;

-- (3) Through pgbouncer: same query, different shape.
--     Run with:  psql -h localhost -p 6432 -U cinetrack -d cinetrack
--     The pid you see now belongs to whichever backend pgbouncer has handed
--     you for THIS transaction. Run BEGIN; the pid; COMMIT; and BEGIN again
--     and you may get a different pid in transaction mode.
BEGIN;
SELECT current_setting('port')                 AS server_port,
       pg_backend_pid()                        AS backend_pid,
       current_setting('application_name')     AS application_name;
COMMIT;

BEGIN;
SELECT pg_backend_pid() AS backend_pid;  -- may be different from the one above
COMMIT;

-- (4) The pgbouncer admin console.
--     Connect with:  psql -h localhost -p 6432 -U cinetrack pgbouncer
--     The "pgbouncer" virtual database is the admin interface.
--     Then run:
--         SHOW POOLS;     -- per-pool client/server counts and waits
--         SHOW STATS;     -- per-database query and prepared-statement counts
--         SHOW SERVERS;   -- the actual backends pgbouncer is multiplexing
--         SHOW CLIENTS;   -- connected clients and which backend (if any) they hold

-- (5) The prepared-statement trap (read this comment carefully).
--     This block uses SQL-text PREPARE/EXECUTE, which is NOT the path
--     pgbouncer's max_prepared_statements feature intercepts. The pgbouncer
--     1.21+ fix is for the protocol-level extended-query path (Parse/Bind/
--     Execute messages) that real drivers use: PgJDBC's prepareStatement,
--     asyncpg, the Go pgx driver, libpq's PQprepare/PQexecPrepared, and so
--     on. Those messages pgbouncer can see and re-prepare on a new backend.
--     SQL-text PREPARE/EXECUTE goes through the simple-query path and is
--     not tracked by max_prepared_statements; it will still break across
--     transaction-mode backend swaps.
--
--     The block below is here to read and to reason about. Running it
--     against pgbouncer:6432 demonstrates the SQL-text path, not the fix.
--     To genuinely demonstrate the protocol-level fix, use a small Python,
--     Go, or Java script that issues prepared statements through the
--     extended-query protocol and run it against pgbouncer:6432 versus
--     postgres:5432. Inspect the result with the SHOW STATS command in
--     section (4) above; the prepared-statement counter only moves on the
--     protocol-level path.
PREPARE rated_by(BIGINT) AS
    SELECT m.title, r.score
    FROM ratings r
    JOIN movies m ON m.id = r.movie_id
    WHERE r.user_id = $1
    ORDER BY r.rated_at DESC
    LIMIT 5;

EXECUTE rated_by(1);
EXECUTE rated_by(2);
EXECUTE rated_by(3);
DEALLOCATE rated_by;

-- (6) Inspect prepared statements in the current backend.
--     pg_prepared_statements is per-session, so it shows what THIS backend
--     currently has cached. With protocol-level support enabled, expect to
--     see the application's prepared statements appear after a few queries.
SELECT name, statement, prepare_time
FROM pg_prepared_statements
ORDER BY prepare_time DESC
LIMIT 10;

-- (7) The SET vs SET LOCAL gotcha.
--     SET LOCAL applies to the current transaction only. Safe in transaction
--     mode. SET (without LOCAL) tries to apply to the whole session and is
--     therefore fragile in transaction mode, because the next transaction
--     may run on a different backend.
BEGIN;
SET LOCAL timezone = 'UTC';
SHOW timezone;          -- UTC inside this transaction
COMMIT;
SHOW timezone;          -- back to the cluster default in the next txn

-- (8) Watching pgbouncer multiplex backends.
--     Open three psql sessions through pgbouncer (port 6432). In each one:
--         BEGIN;
--         SELECT pg_backend_pid(), pg_sleep(15);
--         COMMIT;
--     Then in a fourth psql, connect to the admin console and run:
--         SHOW POOLS;    -- expect cl_active = 3, sv_active = 3
--     The cl_active is your three clients. sv_active is the three Postgres
--     backends pgbouncer has loaned to them. While the SELECTs are running,
--     no other client can claim those backends.

-- (9) Pool exhaustion in slow motion.
--     Set default_pool_size = 2 in pgbouncer.ini and restart pgbouncer.
--     Open three sessions, each running pg_sleep(20) in a transaction.
--     The third session's BEGIN will block waiting for a backend. From the
--     admin console:
--         SHOW POOLS;    -- cl_active = 2, cl_waiting = 1, sv_active = 2
--     The cl_waiting > 0 line is the symptom every undersized pool shows.

-- (10) Counting backends Postgres actually sees.
--      Connect direct (port 5432) and run this regardless of how many
--      pgbouncer clients are open. The count is bounded by pgbouncer's
--      default_pool_size (plus whatever direct connections exist), not by
--      the application's client connection count.
SELECT count(*) AS real_backends,
       count(*) FILTER (WHERE state = 'active')   AS active_backends,
       count(*) FILTER (WHERE state = 'idle')     AS idle_backends
FROM pg_stat_activity
WHERE backend_type = 'client backend';
