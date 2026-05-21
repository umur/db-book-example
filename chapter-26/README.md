# Chapter 26 sandbox

A single-node Postgres 17 cluster with a pgBackRest sidecar. The
backup repository lives on a local Docker volume that stands in for
S3; the same configuration translates to a real bucket with three
changes (`repo1-type=s3`, an access key, and a bucket name).

The point of this sandbox is to make point-in-time recovery
reproducible end to end. The `pitr-walkthrough.md` runs you through
ten steps: stanza setup, full backup, a destructive `DELETE`, and
recovery to one second before the mistake. Run the walkthrough at
least once before reading section 26.5 of the book; the chapter walks
through the same sequence at a higher level.

## Bring it up

```bash
docker compose up -d
```

Wait about ten seconds for Postgres to bootstrap and pgBackRest to
install in both containers. Then verify the seed loaded:

```bash
docker exec -it cinetrack-pg-26 \
    psql -U postgres -d cinetrack -c "SELECT count(*) FROM reviews"
```

Expected: `800`.

## Run the walkthrough

Follow `pitr-walkthrough.md` step by step. The full sequence takes
about ten minutes the first time and five minutes the second time.

## Tear down

```bash
docker compose down -v
```

The `-v` drops the volumes so the next `up` starts from scratch.

## What's deliberately missing

This is a learning sandbox. Do not copy the configuration into a real
deployment without adding: an S3 bucket as the repository instead of
the local volume, encryption at rest (`repo1-cipher-type`), a second
repository in a different region, REST API authentication for any
operator endpoints, real passwords from a secret store, and a
scheduled `pgbackrest verify` cron job. The chapter explains every one
of these. Read it before you ship.
