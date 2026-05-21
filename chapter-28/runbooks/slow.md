# Runbook: Postgres is slow

Reproduces the scenario from chapter 28.10. The sandbox seeds a
`view_events` table with 200,000 rows; a query that filters on
`viewed_at` without the right index forces a sequential scan. The
runbook walks through the triage tree, finds the bottleneck, and adds
the index.

## Scenario

The application team reports that the "recent views" panel is slow.
The query is:

```sql
SELECT user_id, count(*)
FROM view_events
WHERE viewed_at > now() - interval '1 hour'
GROUP BY user_id
ORDER BY count(*) DESC
LIMIT 10;
```

It used to take 5 ms. It now takes 800 ms. The data has grown; the
index has not.

## Reproduce

Bring up the sandbox and load the seed:

```bash
docker compose up -d postgres
docker exec -it ch28-postgres \
    psql -U cinetrack -d cinetrack -f /seed.sql
```

Run the query with `EXPLAIN`:

```bash
docker exec -it ch28-postgres psql -U cinetrack -d cinetrack -c "
EXPLAIN (ANALYZE, BUFFERS)
SELECT user_id, count(*)
FROM view_events
WHERE viewed_at > now() - interval '1 hour'
GROUP BY user_id
ORDER BY count(*) DESC
LIMIT 10;
"
```

The plan shows a `Seq Scan on view_events` with `Buffers: shared
read=...` in the thousands. That is the bottleneck.

## Triage tree

Walk the levels from chapter 28.10.

### Level 1: is the database actually the problem?

```sql
SELECT pid, state, wait_event_type, wait_event, query
FROM pg_stat_activity
WHERE state != 'idle' AND backend_type = 'client backend';
```

Active queries, no client waits. The database is the bottleneck.

### Level 2: is anything locked?

```sql
SELECT * FROM pg_locks WHERE NOT granted;
```

Nothing blocked. Continue.

### Level 3: which query is slow?

```sql
SELECT query,
       calls,
       round(mean_exec_time::numeric, 2) AS mean_ms,
       round(total_exec_time::numeric, 2) AS total_ms
FROM pg_stat_statements
WHERE query LIKE '%view_events%'
ORDER BY total_exec_time DESC
LIMIT 5;
```

The recent-views query is at the top. `mean_ms` confirms 800 ms.

### Level 4: why is the query slow?

The `EXPLAIN ANALYZE` output already told us: sequential scan. The fix
is an index on `viewed_at`.

## Recover

Add the index without locking the table:

```sql
CREATE INDEX CONCURRENTLY view_events_viewed_at_idx
    ON view_events (viewed_at);
ANALYZE view_events;
```

Re-run the query:

```bash
docker exec -it ch28-postgres psql -U cinetrack -d cinetrack -c "
EXPLAIN (ANALYZE, BUFFERS)
SELECT user_id, count(*)
FROM view_events
WHERE viewed_at > now() - interval '1 hour'
GROUP BY user_id
ORDER BY count(*) DESC
LIMIT 10;
"
```

The plan now uses `Index Scan using view_events_viewed_at_idx`. Buffer
reads drop by an order of magnitude. Mean execution time goes back
into the single-digit-millisecond range.

## Lesson

The bottleneck was a missing index. The reason it became a slow page
was that `pg_stat_statements` was not on the team's dashboard. A daily
review of the top ten queries by total time would have surfaced this
regression hours after the deploy that introduced it. Build the
panel; look at it; do the index work in the daytime.
