# Chapter 4 sandbox

Cinetrack starter wired up to expose the WAL machinery. The compose file
sets `log_checkpoints = on` so every checkpoint prints a summary line to
the container log, and tightens `max_wal_size` and `checkpoint_timeout` so
the chapter's checkpoint behavior is visible without waiting forever.

## Bring it up

```bash
docker compose up -d
psql -h localhost -U cinetrack -d cinetrack -f seed.sql
psql -h localhost -U cinetrack -d cinetrack -f wal-tour.sql
```

In a second terminal, watch checkpoints fire as the tour runs:

```bash
docker logs -f cinetrack-pg-ch04
```

## What to expect

`wal-tour.sql` walks through current LSN, WAL volume measurement, the
`pg_stat_wal` view, a forced `CHECKPOINT`, and a side-by-side latency
comparison of `synchronous_commit = on` versus `off`. The off variant is
typically several times faster on a consumer SSD.

To inspect the raw WAL stream, run `./pg_waldump-demo.sh` from the host.
The script execs into the container and dumps records from the active
segment.

## Tear it down

```bash
docker compose down -v   # -v drops the volume; next `up` starts fresh
```
