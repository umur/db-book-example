# Chapter 25 sandbox

A three-node Patroni cluster on a three-node etcd cluster, with HAProxy
in front for connection routing. Postgres 17 inside the Spilo image,
etcd 3.5, HAProxy 2.9. Six containers plus HAProxy, all on one Docker
network.

The point of this sandbox is to make Patroni's failover behavior
visible and reproducible. The `failover-tour.md` walks through seven
scenarios, from a planned switchover to a forced data-loss case to
losing etcd quorum. Run them in order.

## Bring it up

```bash
docker compose up -d
```

Wait about 20 seconds for etcd to form a quorum and for the three
Patroni nodes to bootstrap. Then verify the cluster is healthy:

```bash
docker exec -it patroni-pg-1 \
    patronictl -c /home/postgres/postgres.yml list
```

Three rows: one Leader, one Sync Standby, one Replica. All running.

The Postgres read-write endpoint is on host port 5432 (HAProxy routes
it to whichever node is the current primary). The read-only endpoint
is on 5433 (round-robin across the replicas). The Patroni REST APIs
are on 8001/8002/8003 (one per node). The HAProxy stats page is on
http://localhost:7000.

## Connect

```bash
# Read-write (always hits the current primary)
psql -h localhost -p 5432 -U cinetrack -d cinetrack

# Read-only (round-robin across healthy replicas)
psql -h localhost -p 5433 -U cinetrack -d cinetrack
```

Password is `cinetrack` for the sandbox.

## Force a failover

The fast version: kill the current leader. Find which node is the
leader from `patronictl list`, then `docker kill patroni-pg-N`. The
cluster takes ~30 seconds (the default failover budget) to elect a new
leader. HAProxy redirects automatically once the new primary is
answering 200 on `/leader`.

Full walkthrough including data-loss vs lossless scenarios, etcd
quorum loss, and pause/resume: `failover-tour.md`.

## Tear it down

```bash
docker compose down -v   # -v drops the volumes; next up starts fresh
```

## What's deliberately missing

This is a learning sandbox. Do not copy the configuration into a real
production cluster without adding: TLS for etcd peer and client traffic,
REST API authentication on every Patroni node, the OS watchdog (the
sandbox has it commented out because Docker containers don't have
`/dev/watchdog`), real passwords from a secret store, and an archive
target for the WAL (the sandbox sets `archive_command` to `/bin/true`
so the WAL just gets discarded).

The chapter explains every one of these. Read it before you ship.
