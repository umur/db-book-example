# Chapter 24 sandbox

Two clusters: a Postgres 15 publisher on port 5415 and a Postgres 17
subscriber on port 5417. This is the upgrade scenario from subchapter
24.4 in miniature: the data lives on Postgres 15, logical replication
ships it to Postgres 17, and the cutover is a connection-string change
in the application.

## Bring it up

```bash
docker compose up -d
psql -h localhost -p 5415 -U cinetrack -d cinetrack -f init.sql
psql -h localhost -p 5415 -U cinetrack -d cinetrack -f seed.sql
psql -h localhost -p 5417 -U cinetrack -d cinetrack -f init.sql
```

`init.sql` runs on both clusters because logical replication does not
ship DDL: the schema must already exist on the subscriber before the
subscription can apply rows.

## Run the tour

`logical-tour.sql` is interactive. The script's comments mark which
session to run each block in. Open two psql windows, one on port 5415
and one on port 5417, and walk through it block by block.

```bash
psql -h localhost -p 5415 -U cinetrack -d cinetrack -f logical-tour.sql
```

## Tear it down

```bash
docker compose down -v   # -v drops both volumes; next `up` is a fresh start
```
