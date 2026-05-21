# Chapter 17 sandbox

Cinetrack with a notification job queue and a transactional outbox wired in.
The schema reuses the cinetrack core (movies, users, reviews, follows) and
adds two queue-style tables: `notifications` (a job queue claimed with
`SKIP LOCKED`) and `outbox` (a publisher log drained by a separate process).
Triggers fire `pg_notify` on inserts so workers can `LISTEN` instead of
polling. Volumes are modest on purpose; this is a hands-on demo, not a
benchmark.

## Bring it up

```bash
docker compose up -d
psql -h localhost -U cinetrack -d cinetrack -f seed.sql
psql -h localhost -U cinetrack -d cinetrack -f queue-tour.sql
```

`init.sql` runs automatically on first boot via the docker-entrypoint mount.

## What to expect

`queue-tour.sql` walks twelve numbered sections: the fanout-in-a-transaction
write, the partial-index claim plan, the single-statement `SKIP LOCKED`
claim, a multi-worker simulation, exponential-backoff failure, the outbox
publisher loop, the `LISTEN`/`NOTIFY` wakeup, dead-letter triage, and a
stuck-row sweeper. Sections 5 and 9 explicitly call for a second `psql`
session.

## Tear it down

```bash
docker compose down -v   # -v drops the volume; next `up` starts fresh
```
