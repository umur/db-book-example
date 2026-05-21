# Chapter 10 sandbox

Cinetrack scaled for the specialty index tour. Same shape as chapter-9,
with a 10-million-row `view_events` table so BRIN's size win against
B-tree is visible in `pg_relation_size`.

## Bring it up

```bash
docker compose up -d
psql -h localhost -U cinetrack -d cinetrack -f extensions.sql
psql -h localhost -U cinetrack -d cinetrack -f seed.sql
psql -h localhost -U cinetrack -d cinetrack -f specialty-tour.sql
```

The seed inserts ~10M `view_events` rows via `generate_series`, so it
takes a minute or two on a laptop.

## What the tour covers

Ten numbered sections in `specialty-tour.sql`: GIN on a `TEXT[]` column,
GIN on JSONB, the GiST `EXCLUDE` constraint demo, BRIN vs B-tree on a
huge time-series column, Hash on long opaque tokens, `pg_trgm` GIN and
GiST, the `bloom` index, GIN expression indexes for full-text search,
and a closing index audit.

## Tear it down

```bash
docker compose down -v
```
