# PITR walkthrough

A guided tour of the chapter-26 sandbox. Bring the cluster up first
(see `README.md`), then run through the steps below in order. Each one
mirrors a step from the chapter, in the same order, against a real
Postgres + pgBackRest pair.

The container names are `cinetrack-pg-26` (Postgres) and
`cinetrack-pgbackrest-26` (the pgBackRest tools sidecar). Every
`pgbackrest` command runs from inside the sidecar.

## 0. Verify the cluster is healthy

```bash
docker exec -it cinetrack-pg-26 \
    psql -U postgres -d cinetrack -c "SELECT count(*) FROM reviews"
```

Expected output: `count = 800`. The seed script populated 800 reviews
during container start.

## 1. Initialize the stanza

pgBackRest needs to know about the cluster before it can back it up:

```bash
docker exec -it cinetrack-pgbackrest-26 \
    pgbackrest --stanza=cinetrack stanza-create
```

Then verify the stanza is healthy. This forces a WAL segment switch
and waits for the segment to arrive in the repository, so it doubles
as an end-to-end check that `archive_command` is working:

```bash
docker exec -it cinetrack-pgbackrest-26 \
    pgbackrest --stanza=cinetrack check
```

Expected: `INFO: stanza-create for stanza 'cinetrack' on repo1` and
`INFO: check command end: completed successfully`.

## 2. Take the first full backup

```bash
docker exec -it cinetrack-pgbackrest-26 \
    pgbackrest --stanza=cinetrack --type=full backup
```

The first full backup runs in about a minute on the sandbox. After it
finishes, list the backup state:

```bash
docker exec -it cinetrack-pgbackrest-26 \
    pgbackrest --stanza=cinetrack info
```

Expected: one full backup entry with a status of `ok`, a timestamp, and
a WAL range.

## 3. Generate some traffic and capture the recovery target

We want a recovery target that lands cleanly between two events. Write
a row, capture the timestamp into a shell variable, then run the
disaster after a one-second pause.

```bash
TARGET="$(docker exec cinetrack-pg-26 \
    psql -U postgres -d cinetrack -tA -c "
INSERT INTO audit_log (note) VALUES ('Pre-disaster sentinel row');
SELECT now()::text;
")"
echo "Recovery target: $TARGET"

# Wait one second so the recovery target is unambiguous.
sleep 1

# Now the disaster, plus a post-disaster audit row to prove recovery
# excludes it.
docker exec -it cinetrack-pg-26 \
    psql -U postgres -d cinetrack <<'SQL'
DELETE FROM reviews;
INSERT INTO audit_log (note) VALUES ('Post-disaster row, should NOT survive recovery');
SQL
```

Confirm the table is empty and the post-disaster row is present:

```bash
docker exec -it cinetrack-pg-26 \
    psql -U postgres -d cinetrack -c "SELECT count(*) FROM reviews"
docker exec -it cinetrack-pg-26 \
    psql -U postgres -d cinetrack -c "SELECT note FROM audit_log ORDER BY id"
```

Expected: 0 reviews, three audit rows.

## 4. Confirm the recovery target

`$TARGET` already holds the timestamp from just before the DELETE. In a
real incident the timestamp would come from the application's audit
trail or Postgres logs configured with `log_line_prefix = '%m [%p] '`.
For the sandbox, the captured `$TARGET` is sufficient:

```bash
echo "Will recover to: $TARGET"
```

## 5. Force a WAL switch so the recent activity is archived

PITR replays WAL up to the target. The WAL segment containing your
target time has to be in the archive. Force a switch:

```bash
docker exec -it cinetrack-pg-26 \
    psql -U postgres -d cinetrack -c "SELECT pg_switch_wal()"
```

The `archive_timeout = 60` in the compose file would force a switch
within a minute anyway, but a manual switch makes the timing
predictable for the walkthrough.

## 6. Stop Postgres and clear PGDATA

The recovery is destructive. We are going to replace the data
directory with the backup, then replay WAL forward to the target.

```bash
docker exec -it cinetrack-pg-26 \
    pg_ctl -D /var/lib/postgresql/data stop -m fast
docker exec -it cinetrack-pg-26 \
    bash -c "rm -rf /var/lib/postgresql/data/* /var/lib/postgresql/data/.??*"
```

(In a real recovery, you would do this on a *new* host, not the
running primary. The sandbox uses one container for clarity.)

## 7. Run the restore

```bash
docker exec -it cinetrack-pgbackrest-26 \
    pgbackrest --stanza=cinetrack \
        --type=time \
        --target="$TARGET" \
        --target-action=promote \
        restore
```

(If you skipped step 4, replace `"$TARGET"` with a real timestamp
string in `'YYYY-MM-DD HH:MM:SS+00'` format.)

The restore copies the full backup's contents into the empty data
directory, writes `recovery.signal`, and sets the recovery target.
On the sandbox this finishes in seconds.

## 8. Start Postgres and watch it replay

```bash
docker exec -d cinetrack-pg-26 \
    pg_ctl -D /var/lib/postgresql/data -l /tmp/postgres.log start
sleep 3
docker exec cinetrack-pg-26 tail -50 /tmp/postgres.log
```

Look for these log lines:

```
LOG:  starting point-in-time recovery to <your target>
LOG:  restored log file "..." from archive
LOG:  consistent recovery state reached at <LSN>
LOG:  recovery stopping before commit of transaction <xid>, time <after target>
LOG:  archive recovery complete
```

The "recovery stopping before commit" line confirms Postgres detected
the next transaction would cross the target time and stopped replay.

## 9. Verify the recovery

```bash
docker exec -it cinetrack-pg-26 \
    psql -U postgres -d cinetrack -c "SELECT count(*) FROM reviews"
docker exec -it cinetrack-pg-26 \
    psql -U postgres -d cinetrack -c "SELECT note FROM audit_log ORDER BY id"
```

Expected:

- 800 reviews (the destructive DELETE was rolled back).
- The audit log has the seed row, the "Pre-disaster sentinel row", but
  *not* the "Post-disaster row" (it was committed after the recovery
  target, so recovery excluded it).

That is the full PITR sequence: a destructive accident, a backup
chosen as the starting point, a target time before the accident, and
a recovered cluster that has the data exactly as it was at the
target.

## 10. Tear down

```bash
docker compose down -v   # -v drops the volumes; next `up` starts fresh
```
