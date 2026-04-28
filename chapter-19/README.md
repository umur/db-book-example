# Chapter 19 sandbox

Postgres 17 with pgbouncer 1.22 in front, configured for transaction-pool
mode and protocol-level prepared statements. Two ports are exposed on
purpose so you can compare direct and pooled behavior side by side.

- `5432` connects directly to Postgres. Use this for seeding and for
  observing real backends in `pg_stat_activity`.
- `6432` connects through pgbouncer. Use this for everything an
  application would do.

## Bring it up

```bash
docker compose up -d
psql -h localhost -p 5432 -U cinetrack -d cinetrack -f seed.sql
psql -h localhost -p 6432 -U cinetrack -d cinetrack -f pooling-tour.sql
```

`init.sql` runs automatically on first boot via the docker-entrypoint mount.

## What to expect

`pooling-tour.sql` walks ten numbered sections: a direct vs. pooled
connection comparison, the pgbouncer admin console (`SHOW POOLS`,
`SHOW STATS`), the prepared-statement demo, the `SET` vs `SET LOCAL` gotcha,
and a pool-exhaustion walkthrough that requires a few extra `psql` sessions.
The point is to see backend recycling happen, not to hit a benchmark target.

## Tear it down

```bash
docker compose down -v   # -v drops the volume; next `up` starts fresh
```
