# Chapter 22 sandbox

Two-container Postgres 17 sandbox: a primary on port 5432 and a streaming
standby on port 5433. The standby bootstraps itself with `pg_basebackup` on
first boot, creates a physical replication slot called `standby_1`, and
streams WAL from the primary in real time.

## Bring it up

```bash
docker compose up -d
psql -h localhost -p 5432 -U cinetrack -d cinetrack -f seed.sql
psql -h localhost -p 5432 -U cinetrack -d cinetrack -f replication-tour.sql
```

In a second terminal, watch the standby catch up:

```bash
docker logs -f cinetrack-pg-ch22-standby
```

You can also connect directly to the standby on port 5433 and run read-only
queries against the replicated data:

```bash
psql -h localhost -p 5433 -U cinetrack -d cinetrack -c \
  "SELECT count(*) FROM reviews;"
```

## What to expect

`replication-tour.sql` walks through `pg_stat_replication`, lag arithmetic in
bytes, the orphaned-slot disaster (a slot with no consumer pinning WAL),
logical slot creation with `pgoutput` and `wal2json`, and reading decoded
events with `pg_logical_slot_peek_changes`. Every section maps to a numbered
moment in the chapter prose.

## Tear it down

```bash
docker compose down -v   # -v drops both volumes; next `up` reseeds the standby
```
