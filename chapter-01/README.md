# Chapter 1 sandbox

The starter cinetrack environment. Postgres 17 in one container, seeded with
about 100 movies, 50 users, 500 ratings, and 50 reviews. Just enough rows to
run the chapter's MVCC peeks and the first `EXPLAIN`.

## Bring it up

```bash
docker compose up -d
```

The `init.sql` runs automatically on first boot via the
`docker-entrypoint-initdb.d` mount, so the schema is ready as soon as the
container is healthy.

## Seed it

```bash
psql -h localhost -U cinetrack -d cinetrack -f seed.sql
```

Re-runnable: the script truncates and re-inserts. The final `SELECT` prints
row counts so you can verify.

## Run the chapter queries

```bash
psql -h localhost -U cinetrack -d cinetrack -f queries.sql
```

Or, more useful, open `psql` interactively and step through `queries.sql` one
section at a time. The numbered comments map directly to moments in the
chapter prose.

## Tear it down

```bash
docker compose down -v   # -v drops the volume; next `up` starts fresh
```

## Break things

This sandbox is yours. Drop indexes, force bloat, hold transactions open. Nothing here is precious. The faster you start treating the database as something to experiment on, the faster expert Postgres becomes a reflex.
