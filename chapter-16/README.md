# Chapter 16 sandbox

Cinetrack repackaged for the concurrency-patterns tour. The schema adds a
`version` column to `reviews`, aggregate columns to `movies`, a `jobs` table
for the SKIP LOCKED queue demo, and an `idempotency_keys` table.

## Bring it up

```bash
docker compose up -d
psql -h localhost -U cinetrack -d cinetrack -f seed.sql
psql -h localhost -U cinetrack -d cinetrack -f concurrency-tour.sql
```

Sections 1, 4, and 11 of the tour need two or more psql sessions to show
contention. Open them interactively. Each numbered block matches a moment in
the chapter prose.

## What to expect

Twelve annotated demos. SKIP LOCKED claims a different job per worker,
advisory locks coordinate cross-cutting work, optimistic version checks
catch concurrent edits, idempotency keys deduplicate retried requests, and
the rating-update CTE upserts the row and adjusts the aggregate in one
transaction. Chapter 17 builds the full queue and outbox on top of these
primitives.

## Tear it down

```bash
docker compose down -v   # -v drops the volume; next `up` starts fresh
```
