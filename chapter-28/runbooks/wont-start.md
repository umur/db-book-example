# Runbook: the database won't start

Reproduces the scenario from chapter 28.9. The sandbox is reproducible
but cannot reproduce real on-disk corruption safely; this runbook
focuses on the two recoverable causes you can practice in the sandbox:
permission damage and a stale PID file.

## Scenario A: permissions on the data directory

Postgres refuses to start because the data directory is not owned by
the postgres user, or the permissions are not 0700.

### Reproduce

Stop the container, break permissions, restart:

```bash
docker exec -it ch28-postgres \
    chmod 0755 /var/lib/postgresql/data
docker compose restart postgres
```

Tail the log:

```bash
docker logs ch28-postgres 2>&1 | tail -n 30
```

The error is `data directory ... has invalid permissions`.

### Recover

Fix the permissions and restart:

```bash
docker exec -u root ch28-postgres \
    chmod 0700 /var/lib/postgresql/data
docker exec -u root ch28-postgres \
    chown -R postgres:postgres /var/lib/postgresql/data
docker compose restart postgres
```

Postgres comes back up.

## Scenario B: a stale postmaster.pid

A previous Postgres process exited uncleanly. The PID file is still
there, pointing at a PID that no longer belongs to Postgres. Postgres
refuses to start because it sees the file and cannot tell whether the
old process is still alive.

### Reproduce

```bash
docker exec -it ch28-postgres pg_ctl -D /var/lib/postgresql/data stop -m immediate
docker exec -it ch28-postgres ls /var/lib/postgresql/data/postmaster.pid
docker exec -u root ch28-postgres \
    sed -i 's/^[0-9]*/99999/' /var/lib/postgresql/data/postmaster.pid
docker compose restart postgres
docker logs ch28-postgres 2>&1 | tail -n 20
```

The error mentions the lock file and an unknown PID.

### Recover

Verify no real Postgres process is running, then delete the stale file:

```bash
docker exec ch28-postgres ps aux | grep '[p]ostgres -D' || true
docker exec -u root ch28-postgres \
    rm /var/lib/postgresql/data/postmaster.pid
docker compose restart postgres
```

Postgres comes back up.

## Scenario C: corruption (read-only walkthrough)

Real `pg_resetwal` cases need a real broken cluster, which is not
something a sandbox should reproduce safely. The chapter (28.9) has the
full walkthrough. The condensed action list:

1. Stop the database.
2. Snapshot the data directory: `cp -a /var/lib/postgresql/data /var/lib/postgresql/data.snapshot`.
3. Restore from backup if you have one. Use point-in-time recovery to
   land just before the corruption.
4. If no backup, `pg_resetwal -D /var/lib/postgresql/data` is the last
   resort. After it succeeds, `pg_dumpall` immediately, restore into a
   fresh cluster, and discard the original.

## Lesson

Two of the three causes here are operational, not corruption.
Permissions break when somebody changed the data dir from outside
Postgres. Stale PID files happen after `kill -9` or container crashes.
The third one is the one you cannot afford to be unprepared for: the
backup story (chapter 26) is what gets you out of real corruption.
Test the backup quarterly. Test the restore quarterly. Catch the
silent backup failures before they become 6am incidents.
