# Chapter 18 sandbox

The cinetrack starter, repackaged for the vacuum, bloat, and wraparound tour.
The schema is a focused subset of the cinetrack core: movies, users, and a
high-update reviews table that bloats fast under simulated edit traffic.
The new files are `extensions.sql` and `vacuum-tour.sql`. The tour script
forces bloat, measures it with `pgstattuple`, reclaims it, applies per-table
autovacuum tuning, and walks through wraparound monitoring queries.

## Bring it up

```bash
docker compose up -d
psql -h localhost -U cinetrack -d cinetrack -f seed.sql
psql -h localhost -U cinetrack -d cinetrack -f extensions.sql
psql -h localhost -U cinetrack -d cinetrack -f vacuum-tour.sql
```

## Running pg_repack

`pg_repack` is not part of the postgres image. Run it from a separate
container pointed at the sandbox:

```bash
docker run --rm --network host \
    -e PGPASSWORD=cinetrack \
    pgrepack/pgrepack:latest \
    pg_repack -h host.docker.internal -U cinetrack -d cinetrack -t reviews \
    --no-superuser-check
```

## Tear it down

```bash
docker compose down -v   # -v drops the volume; next `up` starts fresh
```
