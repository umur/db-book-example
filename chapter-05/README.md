# Chapter 5 sandbox

A larger cinetrack dataset (500k `view_events`) running against an
intentionally small Postgres: `shared_buffers = 256MB`, `work_mem = 8MB`,
`effective_cache_size = 512MB`. Those settings are what make the spill in
section (6) of `memory-tour.sql` show up on a laptop.

## Bring it up

```bash
docker compose up -d
psql -h localhost -U cinetrack -d cinetrack -f seed.sql
psql -h localhost -U cinetrack -d cinetrack -f memory-tour.sql
```

The seed step takes a minute. 500k rows are enough to make the sort
visibly spill to disk under 8MB of `work_mem`, which is the point.

## What to expect

Section (6) ends with `Sort Method: external merge  Disk: ...kB`. Section (7)
runs the same query after `SET work_mem = '64MB'` and gets `Sort Method:
quicksort  Memory: ...kB`. That diff is the chapter's central piece of
operational evidence: `work_mem` is per-operation, per-backend, and small
changes flip the plan from spilling to in-memory.

## Tear it down

```bash
docker compose down -v   # -v drops the volume
```
