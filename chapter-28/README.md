# Chapter 28 sandbox

A single Postgres 17 container, plus an optional standby, plus a
commented Citus sketch. The chapter is the closer of the book and is
mostly runbooks; this sandbox is the box you bring up when you want to
reproduce one of the five emergencies on your own machine instead of
in production.

## Bring it up

```bash
docker compose up -d postgres
```

The seed data loads from `init.sql` automatically. To add the larger
`view_events` and `reviews` populations:

```bash
docker exec -it ch28-postgres \
    psql -U cinetrack -d cinetrack -f /seed.sql
```

Connect with:

```bash
psql -h localhost -p 5432 -U cinetrack -d cinetrack
# password: cinetrack
```

## The runbooks

Each file in `runbooks/` is a self-contained reproduction. Read the
chapter's runbook subchapter first, then run the matching scenario
from this directory:

| Chapter section | Runbook file               |
|-----------------|----------------------------|
| 28.6            | `runbooks/disk-full.md`    |
| 28.7            | `runbooks/replication-broke.md` |
| 28.8            | `runbooks/vacuum-falling-behind.md` |
| 28.9            | `runbooks/wont-start.md`   |
| 28.10           | `runbooks/slow.md`         |

The order is the order the chapter walks through. Each runbook starts
clean from the sandbox state, so you can run them in any order.

## The Citus sketch

`docker-compose.yml` has a commented section that brings up a Citus
coordinator and two workers. It is a sketch, not a production cluster:
no Patroni, no separate volumes, no TLS, no monitoring. The point is to
let you run `SELECT create_distributed_table(...)` and see the
mechanics, not to run a real shard. Read chapter 28.4 first, then
uncomment if you want to experiment.

## Tear it down

```bash
docker compose down -v
```

The `-v` drops the named volumes; the next `up -d` starts fresh.
