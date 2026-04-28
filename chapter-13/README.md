# Chapter 13 sandbox

Cinetrack with full-text search wired in. The schema is the same shape as
chapter-9 plus two `tsvector` columns and four GIN indexes: the canonical FTS
pattern from section 13.4, plus trigram indexes for the fuzzy-fallback path
from 13.6. Seed volumes are 50,000 movies and 100,000 reviews, enough that
the GIN-vs-sequential-scan difference shows up in plans.

## Bring it up

```bash
docker compose up -d
psql -h localhost -U cinetrack -d cinetrack -f seed.sql
psql -h localhost -U cinetrack -d cinetrack -f fts-tour.sql
```

`extensions.sql` and `init.sql` run automatically on first boot via the
docker-entrypoint mount; you only run them manually if you reset the volume
without restarting the container.

## What to expect

`fts-tour.sql` walks twelve numbered sections covering tokenization,
weighted multi-column vectors, ranked search, trigram fallback, snippets,
and the wrong-way pattern that bypasses the GIN index. Compare the plans
on sections 3 and 11 to see why storing the `tsvector` in a generated
column matters.

## Tear it down

```bash
docker compose down -v   # -v drops the volume; next `up` starts fresh
```
