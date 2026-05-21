# Runbook: vacuum falling behind

Reproduces the scenario from chapter 28.8. The sandbox is small, so
"falling behind" is reproduced by holding open a long-running
transaction that pins the visibility horizon and stops vacuum from
making progress.

## Scenario

A psql session in another terminal opens a transaction and then idles.
The application keeps updating rows on the `reviews` table. Autovacuum
runs but cannot mark dead rows as reusable because the idle session's
snapshot still needs them. Bloat climbs; the table size grows while the
live row count stays flat.

## Reproduce

Bring up the sandbox if it isn't running:

```bash
docker compose up -d postgres
```

In one terminal, open a transaction and idle:

```bash
docker exec -it ch28-postgres psql -U cinetrack -d cinetrack
```

```sql
BEGIN;
SELECT count(*) FROM reviews;
-- Leave this session open. Do not COMMIT or ROLLBACK.
```

In a second terminal, run an update loop that touches every row:

```bash
docker exec -it ch28-postgres psql -U cinetrack -d cinetrack -c "
DO \$\$
BEGIN
    FOR i IN 1..10 LOOP
        UPDATE reviews SET updated_at = now() WHERE id % 10 = i % 10;
        PERFORM pg_sleep(1);
    END LOOP;
END\$\$;
"
```

Watch the bloat metric climb:

```sql
SELECT relname,
       n_live_tup, n_dead_tup,
       round(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 1) AS dead_pct,
       pg_size_pretty(pg_total_relation_size(relid)) AS total_size
FROM pg_stat_user_tables
WHERE relname = 'reviews';
```

`dead_pct` climbs past 50%. Autovacuum has run but has not been able to
reclaim anything because the idle session's `backend_xmin` is pinning
the horizon.

## Recover

Find the blocker:

```sql
SELECT pid, usename, state,
       now() - xact_start AS xact_age,
       backend_xmin,
       age(backend_xmin) AS xmin_age
FROM pg_stat_activity
WHERE backend_xmin IS NOT NULL
ORDER BY backend_xmin
LIMIT 5;
```

Terminate the offending session:

```sql
SELECT pg_terminate_backend(<pid>);
```

Force a manual vacuum on the affected table:

```sql
VACUUM (FREEZE, VERBOSE, ANALYZE) reviews;
```

Verify the bloat is reclaimed:

```sql
SELECT relname,
       n_live_tup, n_dead_tup,
       pg_size_pretty(pg_total_relation_size(relid)) AS total_size
FROM pg_stat_user_tables
WHERE relname = 'reviews';
```

`n_dead_tup` should drop close to zero.

## Lesson

The cause was an idle-in-transaction session. The fix is two settings
the sandbox does not enforce by default but every production system
should:

```sql
ALTER SYSTEM SET idle_in_transaction_session_timeout = '5min';
ALTER SYSTEM SET statement_timeout = '30min';
SELECT pg_reload_conf();
```

With those in place, the offending session would have been terminated
automatically after five minutes.
