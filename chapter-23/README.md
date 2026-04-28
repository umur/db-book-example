# Chapter 23 sandbox

A three-node Postgres 17 streaming replication topology. The `primary`
runs the `cinetrack` schema and accepts writes. The `standby` streams
WAL directly from the primary. The `cascade` replica streams from the
standby, not from the primary, demonstrating cascading replication.

## Bring it up

```bash
chmod +x bootstrap-standby.sh bootstrap-cascade.sh
docker compose up -d
```

The `bootstrap-standby.sh` and `bootstrap-cascade.sh` scripts run on
first start. They use `pg_basebackup` to seed each replica from its
upstream, install the recovery configuration, and hand off to the
normal Postgres entrypoint. The schema and seed run on the primary
via the standard `docker-entrypoint-initdb.d` hook.

Hosts after startup:

| Role     | Port | Purpose                                |
| -------- | ---- | -------------------------------------- |
| primary  | 5432 | Writes, schema, seed                   |
| standby  | 5433 | Streams from primary, also a cascade source |
| cascade  | 5434 | Streams from standby, leaf in the tree |

## Run the tour

`streaming-tour.sql` is not meant to be run end-to-end against a single
host. The script targets three different nodes (primary, standby,
cascade) and each section is annotated with the host it should run
against. Open three `psql` sessions and run the numbered sections in
the indicated session:

```bash
# Session 1: primary (writes)
psql -h localhost -p 5432 -U cinetrack -d cinetrack

# Session 2: standby (reads, conflicts)
psql -h localhost -p 5433 -U cinetrack -d cinetrack

# Session 3: cascade leaf
psql -h localhost -p 5434 -U cinetrack -d cinetrack
```

`streaming-tour.sql` walks through the chapter's eleven experiments:
verifying the topology, measuring lag from both sides, reproducing a
recovery conflict, flipping `hot_standby_feedback` on and off, and
discovering the cascade tier from each node.

## Tear it down

```bash
docker compose down -v   # -v drops the volumes; next `up` starts fresh
```
