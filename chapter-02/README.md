# Chapter 2 sandbox

Same cinetrack starter from Chapter 1, repackaged for the MVCC tour. The
schema and seed are identical; the new file is `mvcc-tour.sql`, twelve
annotated sections that walk through tuple headers, snapshots, the update
illusion, dead-tuple growth, vacuum reclamation, HOT versus non-HOT, and the
long-transaction trap.

## Bring it up

```bash
docker compose up -d
psql -h localhost -U cinetrack -d cinetrack -f init.sql
psql -h localhost -U cinetrack -d cinetrack -f seed.sql
psql -h localhost -U cinetrack -d cinetrack -f mvcc-tour.sql
```

Run `init.sql` first on a fresh database. `seed.sql` starts with a `TRUNCATE` over all tables and will fail if those tables don't exist yet.

The first run of `mvcc-tour.sql` won't show much for the long-transaction
section because both psql sessions are needed. Open it interactively and step
through the numbered blocks.

## What to expect

Repeated updates make `n_dead_tup` climb visibly on `reviews`. Vacuum brings
it back to zero. The on-disk heap size won't shrink: vacuum reclaims internal
space, not the file itself. That's the operational tax discussed in section
2.7. Chapter 18 covers how production teams keep that tax in check.

## Tear it down

```bash
docker compose down -v   # -v drops the volume; next `up` starts fresh
```
