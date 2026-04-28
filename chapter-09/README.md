# Chapter 9 sandbox

Cinetrack scaled up for the indexing tour: 50,000 movies, 10,000 users,
500,000 ratings, 50,000 reviews, 50,000 notifications. Big enough that
bad indexes hurt visibly; small enough to run on a laptop.

## Bring it up

```bash
docker compose up -d
psql -h localhost -U cinetrack -d cinetrack -f seed.sql
psql -h localhost -U cinetrack -d cinetrack -f indexing-tour.sql
```

The tour is twelve numbered sections covering multi-column ordering,
partial indexes, expression indexes, covering indexes with `INCLUDE`,
the visibility-map dependency of index-only scans, unique and exclusion
constraints, `CREATE INDEX CONCURRENTLY`, and an unused-index audit
query.

## What to expect

`EXPLAIN (ANALYZE, BUFFERS)` runs throughout the tour. Watch the plan
flip from `Seq Scan` to `Index Scan` to `Index Only Scan`. Watch
`Heap Fetches` drop to zero on the covering index, then climb after an
update, then drop again after vacuum. The numbers are what the chapter
prose asserts; here you see them on your own machine.

## Tear it down

```bash
docker compose down -v   # -v drops the volume; next `up` starts fresh
```
