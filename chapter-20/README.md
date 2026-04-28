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

## Tear it down

```bash
docker compose down -v   # -v drops the volume; next `up` starts fresh
```
