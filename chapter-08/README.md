# Chapter 8 sandbox

Cinetrack scaled up to ~50,000 movies and ~500,000 ratings. The bigger
volume is what makes the EXPLAIN walkthroughs behave like production:
misplans actually look bad, and good plans show their work.

## Bring it up

```bash
docker compose up -d
psql -h localhost -U cinetrack -d cinetrack -f init.sql
psql -h localhost -U cinetrack -d cinetrack -f seed.sql
psql -h localhost -U cinetrack -d cinetrack -f explain-walkthroughs.sql
```

## What's inside

`explain-walkthroughs.sql` runs eight queries from misplan to fix, each
following the diagnostic loop from section 8.7. Run every query twice
and read the second plan; the first run pays the disk cost.

The walkthroughs cover prefix LIKE indexes, missing join-side indexes,
sort spills, expression indexes, composite-index joins, the visibility
map and Index Only Scan, and a correlated subquery rewrite.

## Tear it down

```bash
docker compose down -v   # -v drops the volume; next `up` starts fresh
```
