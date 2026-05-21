# Chapter 12 sandbox

Cinetrack with a JSONB-rich movies catalog: 50,000 rows, each with a
realistic metadata blob covering languages, alternate titles, awards,
production info, tags, and format. Big enough that bad indexes hurt
visibly; small enough to run on a laptop.

## Bring it up

```bash
docker compose up -d
psql -h localhost -U cinetrack -d cinetrack -f init.sql
psql -h localhost -U cinetrack -d cinetrack -f seed.sql
psql -h localhost -U cinetrack -d cinetrack -f jsonb-tour.sql
```

The tour is twelve numbered sections covering the operator family,
GIN with `jsonb_ops` versus `jsonb_path_ops`, expression indexes for
hot single keys, range and path queries, `jsonb_set` mutations, and
the migration that lifts a hot key out of JSONB into a real column.

## What to expect

`EXPLAIN (ANALYZE, BUFFERS)` runs throughout. Watch plans flip from
`Seq Scan` to `Bitmap Index Scan` to `Index Scan` as the right index
arrives. Compare on-disk sizes between `jsonb_ops` and
`jsonb_path_ops`, then between the GIN index and a single-key
expression index. The numbers are what the chapter prose asserts;
here you see them on your own machine.

## Tear it down

```bash
docker compose down -v   # -v drops the volume; next `up` starts fresh
```
