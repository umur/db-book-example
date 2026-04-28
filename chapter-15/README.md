# Chapter 15 sandbox

Postgres 17 with the cinetrack schema, configured to log lock waits and
keep the deadlock timeout at one second. The new file is `isolation-tour.sql`,
twelve numbered demos that walk through Read Committed surprises, Repeatable
Read serialization failures, Serializable Snapshot Isolation catching write
skew, row-level lock modes (`FOR UPDATE`, `NOWAIT`, `SKIP LOCKED`), deadlock
formation and prevention, and `lock_timeout` in action.

## Bring it up

```bash
docker compose up -d
psql -h localhost -U cinetrack -d cinetrack -f seed.sql
```

## Two-session demos

Most of `isolation-tour.sql` requires two `psql` sessions running side by
side. Open two terminals. Each numbered section in the script names which
session runs which statement. Step through them in order; the script is a
playbook, not a one-shot run.

```bash
# Terminal A
psql -h localhost -U cinetrack -d cinetrack

# Terminal B
psql -h localhost -U cinetrack -d cinetrack
```

The diagnostic query at the bottom (lock-tree from `pg_stat_activity` joined
to `pg_blocking_pids`) is the one to keep nearby in production. It tells
you who is waiting on whom in real time.

## Tear it down

```bash
docker compose down -v   # -v drops the volume; next `up` starts fresh
```
