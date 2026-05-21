# Runbook: replication broke

Reproduces the scenario from chapter 28.7. The sandbox's `standby`
service is a streaming replica of the primary; this runbook stops it,
recycles WAL on the primary past what the standby has, and walks
through the rebuild.

## Scenario

A streaming standby falls behind because it was offline. The primary
recycled WAL the standby still needed. The standby cannot catch up on
its own; the only recovery is a fresh `pg_basebackup`.

## Reproduce

Start the standby:

```bash
docker compose --profile replication up -d standby
```

Wait ten seconds for streaming to stabilize, then verify both sides:

```bash
docker exec -it ch28-postgres psql -U cinetrack -d cinetrack -c \
    "SELECT application_name, state, sync_state, replay_lag
     FROM pg_stat_replication;"

docker exec -it ch28-standby psql -U cinetrack -d cinetrack -c \
    "SELECT pg_is_in_recovery(), pg_last_xact_replay_timestamp();"
```

Stop the standby:

```bash
docker compose stop standby
```

On the primary, drop the slot the standby was using and force WAL to be
recycled by generating a lot of activity and running checkpoints:

```bash
docker exec -it ch28-postgres psql -U cinetrack -d cinetrack -c \
    "SELECT pg_drop_replication_slot('ch28_standby');
     INSERT INTO reviews (user_id, movie_id, body, rating)
     SELECT 1 + (g % 200), 1 + (g % 5), 'noise', 3
     FROM generate_series(1, 100000) g;
     CHECKPOINT;"
```

Run the insert plus checkpoint two or three times. WAL the standby
needed is now gone.

Start the standby again:

```bash
docker compose --profile replication start standby
```

Tail its log:

```bash
docker logs ch28-standby 2>&1 | tail -n 30
```

The error is `requested WAL segment ... has already been removed`.

## Recover

The only recovery is to rebuild the standby from a fresh basebackup.
Stop and clear the standby, then bring it back up; the entrypoint
script in `docker-compose.yml` runs `pg_basebackup` if the data dir is
empty.

```bash
docker compose stop standby
docker compose rm -f standby
docker volume rm ch28_standby_data 2>/dev/null || true

# Recreate the slot the entrypoint expects.
docker exec -it ch28-postgres psql -U cinetrack -d cinetrack -c \
    "SELECT pg_create_physical_replication_slot('ch28_standby');"

docker compose --profile replication up -d standby
```

After ten seconds, both sides report the standby is streaming again:

```bash
docker exec -it ch28-postgres psql -U cinetrack -d cinetrack -c \
    "SELECT application_name, state, replay_lag
     FROM pg_stat_replication;"
```

## Lesson

The standby fell behind because the slot was dropped. The slot was
dropped because the standby was offline and nobody alerted on the
inactive slot retaining WAL. Two lessons: every standby has a slot,
every slot has an alert.
