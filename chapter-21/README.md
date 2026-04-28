# Chapter 21 sandbox

Postgres 17 with the cinetrack schema, configured to log DDL and lock
waits. The `migrations/` directory holds seven numbered SQL files that
walk through each safe migration step from the chapter, and
`migration-tour.sql` runs the full sequence end-to-end while querying
`pg_locks` between steps so the lock acquisition is visible.

## Bring it up

```bash
docker compose up -d
psql -h localhost -U cinetrack -d cinetrack -f seed.sql
```

## Run a single migration step

The files in `migrations/` are numbered in the order they should be
applied. Each one demonstrates one of the patterns from the chapter.

```bash
psql -h localhost -U cinetrack_migrator -d cinetrack \
    -f migrations/01-add-column-nullable.sql
```

The migrator role has `lock_timeout = '5s'` set at the role level, so
even if the script forgets the `SET LOCAL`, the floor is safe.

The migrations split into two workflows:

- `01` through `05` are the **`flagged` column workflow** from
  subchapters 21.4, 21.6, 21.7, and 21.8: add a nullable column,
  backfill it in chunks, add a `NOT VALID` `CHECK` constraint, validate
  the constraint, and finally build a partial index concurrently. Run
  them in order on a fresh sandbox.
- `06` and `07` are the **shadow-column rename workflow** from
  subchapter 21.9, which drops the old `body` column and renames the
  shadow `content` column. They depend on `migration-tour.sql` having
  run first (the tour is what creates the shadow column, installs the
  dual-write trigger, and backfills it). Run `migration-tour.sql`
  first, then `06` and `07` if you want to step through the cleanup
  manually.

## Run the full tour

`migration-tour.sql` is the end-to-end walkthrough. It runs every step
of the safe rename pattern (subchapter 21.9) in order and prints the
state of `pg_locks` between steps. Watch the lock modes change.

```bash
psql -h localhost -U cinetrack_migrator -d cinetrack -f migration-tour.sql
```

## Tear it down

```bash
docker compose down -v   # -v drops the volume; next `up` starts fresh
```
