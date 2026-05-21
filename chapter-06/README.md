# Chapter 6 sandbox

A cinetrack dataset (10k movies, 2M ratings, 5k users, 5k reviews) running against Postgres 17
with the same modest settings as chapter 5. The point of this sandbox is
to make the seq-scan to index-scan transition observable, to expose B-tree
internals through `pageinspect`, and to watch the visibility map flip
under `VACUUM`.

## Bring it up

```bash
docker compose up -d
psql -h localhost -U cinetrack -d cinetrack -f seed.sql
psql -h localhost -U cinetrack -d cinetrack -f extensions.sql
psql -h localhost -U cinetrack -d cinetrack -f index-tour.sql
```

## What to expect

Section (1) of `index-tour.sql` runs the query without an index and shows
a `Seq Scan` plan. Section (2) creates the index and the same query flips
to `Index Scan` with a fraction of the buffer reads. Section (3) builds
a covering index and section (4) shows `Heap Fetches: 0` after `VACUUM`,
which is the visibility-map optimization in action. Sections (6) and (7)
use `pageinspect` to read the B-tree's metapage and per-page stats.
Section (9) makes the indexes bloat, and section (10) rebuilds them with
`REINDEX CONCURRENTLY`.

## Tear it down

```bash
docker compose down -v
```
