## Chapter 14 sandbox

Cinetrack with two `view_events` tables wired in. `view_events_legacy` is
the unpartitioned "before" state every team ships first. `view_events` is
RANGE-partitioned by `occurred_at`, one child partition per month, plus
a default partition. Both hold the same one million rows spread across
13 months so `EXPLAIN` comparisons are honest.

The schema also carries the chapter's smaller demos: narrowed types on
the core tables, a `STORED` generated `tsvector` and `body_length` on
`reviews`, and an `EXCLUDE` constraint on `screen_bookings`.

### Bring it up

```bash
docker compose up -d
psql -h localhost -U cinetrack -d cinetrack -f init.sql
psql -h localhost -U cinetrack -d cinetrack -f seed.sql
psql -h localhost -U cinetrack -d cinetrack -f partitioning-tour.sql
```

`init.sql` runs once automatically on first boot via the
docker-entrypoint mount. Re-running `psql -f init.sql` against an
already-initialized database is safe: every `CREATE` uses
`IF NOT EXISTS`, so subsequent runs are idempotent. The chapter prose
shows the explicit `psql -f init.sql` step so the workflow stays clear
when you reset the database between exercises.

### What to expect

`partitioning-tour.sql` walks twelve numbered sections covering partition
listing, pruning that fires, pruning that doesn't (and why), execution-
time pruning, the legacy-vs-partitioned plan comparison, `ATTACH`,
the migration shape, generated columns, the `EXCLUDE` violation, and
retention via `DETACH` plus `DROP`. Compare sections (4) and (5) to see
why writing `WHERE occurred_at >= '...'` instead of
`WHERE date_trunc('month', occurred_at) = '...'` is the whole game.

### Tear it down

```bash
docker compose down -v   # -v drops the volume; next `up` starts fresh
```
