# Runbook: the disk is full

Reproduces the scenario from chapter 28.6. The sandbox does not have a
small fixed-size volume by default, so the reproduction here uses a
controlled `tmpfs` mount and a tight WAL retention to make "disk full"
visible quickly.

## Scenario

A logical replication slot stops being consumed. WAL piles up in
`pg_wal/`. Within a minute, disk usage on the data volume passes 90%.

## Reproduce

Bring up the sandbox if it is not running:

```bash
docker compose up -d postgres
```

Create an unused logical replication slot:

```bash
docker exec -it ch28-postgres psql -U cinetrack -d cinetrack -c \
    "SELECT pg_create_logical_replication_slot('orphan', 'pgoutput');"
```

Now generate WAL faster than the slot can be advanced (it will never
advance, because nothing is consuming it):

```bash
docker exec -it ch28-postgres psql -U cinetrack -d cinetrack -c "
INSERT INTO reviews (user_id, movie_id, body, rating)
SELECT 1 + (g % 200), 1 + (g % 5), repeat('x', 4096), 1 + (g % 5)
FROM generate_series(1, 200000) g;
"
```

Watch WAL grow:

```bash
docker exec -it ch28-postgres \
    du -sh /var/lib/postgresql/data/pg_wal
```

After two or three iterations of the insert, `pg_wal/` is hundreds of
megabytes and the slot is the cause.

## Recover

Find the slot:

```sql
SELECT slot_name, slot_type, active,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn))
           AS retained_wal
FROM pg_replication_slots
ORDER BY pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) DESC;
```

Drop the orphan slot:

```sql
SELECT pg_drop_replication_slot('orphan');
CHECKPOINT;
```

WAL is reclaimed at the next checkpoint. Verify:

```bash
docker exec -it ch28-postgres \
    du -sh /var/lib/postgresql/data/pg_wal
```

The size should be back under 100 MB.

## Lesson

The fix took two SQL statements. The reason it became an emergency was
that nothing alerted on a slot retaining WAL until disk was at 95%. Add
a `pg_replication_slots` retention alert at 5 GB. The alert is cheap;
the absence of it is what caused the page.
