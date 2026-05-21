# Chapter 20 sandbox

Cinetrack with `pg_stat_statements` and `auto_explain` preloaded. The home
feed query has a baked-in regression at this scale: the planner picks a
hash semijoin over a sequential scan of `reviews`, when the right plan is
a nested loop driven by the followed-user list. The `monitoring-tour.sql`
script walks the full slow-query workflow end to end, catching the
regression with a snapshot diff, reproducing the plan, fixing it with a
composite index, and verifying the fix in `pg_stat_statements`.

## Bring it up

```bash
docker compose up -d
psql -h localhost -U cinetrack -d cinetrack -f init.sql
psql -h localhost -U cinetrack -d cinetrack -f seed.sql
psql -h localhost -U cinetrack -d cinetrack -f monitoring-tour.sql
```

`extensions.sql` runs automatically on first boot. `auto_explain` logs any
query slower than 500ms with full `ANALYZE` and `BUFFERS` output;
`docker compose logs postgres` shows them.

## Integration test

The chapter IT (`Chapter20IT`) spins up a Testcontainers container with
`shared_preload_libraries=pg_stat_statements` set via `withCommand`, so
`pg_stat_statements` is fully operational. The test suite:

- verifies `pg_stat_statements` and `pg_buffercache` extensions install cleanly,
- seeds the full 500k-review dataset and confirms row count,
- runs a known home-feed workload, then asserts `pg_stat_statements` captured
  it with a non-zero call count,
- confirms at least one query has a non-zero `mean_exec_time`,
- runs `EXPLAIN (ANALYZE, BUFFERS)` on the home-feed query and confirms the
  plan is non-empty.

Run the IT alone:

```bash
cd test-harness
mvn failsafe:integration-test failsafe:verify -Dit.test=Chapter20IT
```

## Tear it down

```bash
docker compose down -v   # -v drops the volume; next `up` starts fresh
```
