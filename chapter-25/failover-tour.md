# Failover tour

A guided walkthrough of the chapter-25 sandbox. Bring the cluster up
first (see `README.md`), then run through the scenarios below in order.
Each one demonstrates a different aspect of Patroni's behavior under
failure.

The container names are `patroni-pg-1`, `patroni-pg-2`, `patroni-pg-3`,
`cinetrack-etcd-1` through `-3`, and `cinetrack-haproxy-ch25`. The
`patronictl` command runs from inside any of the Patroni containers.

## 0. Verify the cluster is healthy

```bash
docker exec -it patroni-pg-1 \
    patronictl -c /home/postgres/postgres.yml list
```

Expected output: three rows, one of them `Leader`, the other two
`Replica` (with one of those marked `Sync Standby`). All three should
show `running` and a low `Lag in MB`.

Pick whichever node is the current leader; for the rest of this tour
we'll call it `pg-LEADER` and the sync replica `pg-SYNC`.

## 1. Write some heartbeat rows

Open two terminals.

Terminal 1 (continuous writer against the HAProxy read-write port):

```bash
psql -h localhost -p 5432 -U cinetrack -d cinetrack <<'SQL'
\timing on
DO $$
BEGIN
    LOOP
        INSERT INTO heartbeat DEFAULT VALUES;
        PERFORM pg_sleep(0.1);
    END LOOP;
END$$;
SQL
```

Leave this running. Each iteration inserts one row roughly every 100ms.

Terminal 2 (read replica):

```bash
watch -n 1 'psql -h localhost -p 5433 -U cinetrack -d cinetrack \
    -c "SELECT count(*), max(written_at) FROM heartbeat"'
```

Watch the count tick up.

## 2. Planned switchover

Switchover is the safe, planned failover. The cluster verifies the
candidate is in sync before promoting.

```bash
docker exec -it patroni-pg-1 \
    patronictl -c /home/postgres/postgres.yml \
    switchover --leader pg-LEADER --candidate pg-SYNC --force
```

Watch terminal 1 carefully. You'll see one or two transactions fail with
"server closed the connection unexpectedly" or similar, then writes
resume against the new primary. Terminal 2's count keeps climbing
without going backward; the row count after the switchover is greater
than the row count before. No rows were lost.

Run `patronictl list` again. The leader role has moved.

## 3. Crash the leader (sync replication = zero data loss)

This time we kill the leader, not switchover. With sync replication
configured, the sync replica has every committed row and can promote
losslessly.

Find the current leader from `patronictl list`, then:

```bash
# Replace pg-LEADER with the actual current leader name.
docker kill patroni-pg-LEADER
```

Watch terminal 1. The writes pause for ~30 seconds (the failover budget
with default ttl=30, loop_wait=10, retry_timeout=10). Then writes resume
against the new primary.

Run `patronictl list` from one of the remaining nodes:

```bash
docker exec -it patroni-pg-2 \
    patronictl -c /home/postgres/postgres.yml list
```

The killed node shows up as `unreachable` initially. The other two
nodes have one Leader and one Sync Standby (a sync replica was
promoted; the new sync is the surviving async replica, if there was
one, or `nosync` if not).

Bring the killed node back:

```bash
docker start patroni-pg-LEADER
```

It rejoins as a replica. Patroni runs `pg_rewind` automatically because
the killed node was ahead on the old timeline. Within a minute the
cluster is back to three healthy nodes.

## 4. Crash the leader with sync mode disabled (data loss)

Disable strict sync mode to see the data-loss case. Edit the cluster
config:

```bash
docker exec -it patroni-pg-1 \
    patronictl -c /home/postgres/postgres.yml edit-config
```

In the editor, change:

```yaml
synchronous_mode: false
synchronous_mode_strict: false
```

Save. Patroni applies the change cluster-wide.

Now repeat scenario 3 with one extra step. Run `patronictl list` to
identify the sync replica. Stop it (`docker stop patroni-pg-SYNC`) so
the surviving replica is the async one. Then start the heartbeat writer
in terminal 1, kill the leader, wait for failover, and count rows. With
async replication the row count after failover is *less* than the
highest row written by the heartbeat loop. Look for the gap: the rows
that were committed against the old leader but never made it to the
replica.

Re-enable sync mode (`synchronous_mode: true`, `synchronous_mode_strict:
true`) before continuing.

## 5. Lose etcd quorum

Patroni cannot make decisions without a quorum of the DCS. Kill two
of three etcd nodes:

```bash
docker kill cinetrack-etcd-1 cinetrack-etcd-2
```

Run `patronictl list`. The output is "DCS is not accessible" or similar.

Watch terminal 1 carefully. The current leader detects it cannot reach
etcd within `retry_timeout` seconds (default 10) and self-demotes its
Postgres to read-only. Writes start failing with "cannot execute INSERT
in a read-only transaction."

Bring etcd back:

```bash
docker start cinetrack-etcd-1
```

A two-of-three quorum is now available again. Within `loop_wait`
seconds, Patroni reconnects, takes the lease (the previous leader
re-acquires it because no one else could have taken it during the
outage), and Postgres resumes accepting writes.

This is the conservative behavior. Patroni would rather refuse writes
than guess at the cluster state.

## 6. Pause and unpause

Pause Patroni's automation. Useful for major-version upgrades or
manual `pg_resetwal` recovery.

```bash
docker exec -it patroni-pg-1 \
    patronictl -c /home/postgres/postgres.yml pause
```

Now if you kill the leader, *no failover happens*. Patroni is paused.
The cluster sits there with the leader dead until you resume.

```bash
docker exec -it patroni-pg-1 \
    patronictl -c /home/postgres/postgres.yml resume
```

Failover proceeds the moment Patroni is unpaused.

## 7. Tear down

```bash
docker compose down -v   # -v drops the volumes; next `up` starts fresh
```
