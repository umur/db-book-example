#!/usr/bin/env bash
# Chapter 4 pg_waldump demo.
#
# pg_waldump reads raw WAL segment files and prints a record-by-record
# description. The binary lives in the official Postgres image alongside
# the server, so we run it via `docker exec` against the sandbox container.
#
# Usage:
#   ./pg_waldump-demo.sh
#
# Prereqs:
#   docker compose up -d
#   psql -h localhost -U cinetrack -d cinetrack -f seed.sql
#   psql -h localhost -U cinetrack -d cinetrack -f wal-tour.sql

set -euo pipefail

CONTAINER="cinetrack-pg-ch04"

echo "==> Current WAL position and segment file"
docker exec -u postgres "$CONTAINER" psql -U cinetrack -d cinetrack -c "
  SELECT pg_current_wal_lsn() AS lsn,
         pg_walfile_name(pg_current_wal_lsn()) AS segment;
"

# Grab the active segment name into a shell variable.
SEGMENT="$(docker exec -u postgres "$CONTAINER" psql -U cinetrack -d cinetrack -tAc "
  SELECT pg_walfile_name(pg_current_wal_lsn());
")"

echo ""
echo "==> Dumping the first 30 records of segment $SEGMENT"
echo "    (rmgr = resource manager, lsn = position, desc = operation)"
echo ""

docker exec -u postgres "$CONTAINER" \
  pg_waldump --limit=30 "/var/lib/postgresql/data/pg_wal/$SEGMENT" \
  || true

echo ""
echo "==> Distribution of record kinds in the segment"
docker exec -u postgres "$CONTAINER" \
  pg_waldump --stats "/var/lib/postgresql/data/pg_wal/$SEGMENT" \
  || true

# Notes:
# - The "FPI" column in --stats is the full-page-image volume. Right after a
#   checkpoint it dominates; later in the cycle it shrinks.
# - Filter by resource manager with --rmgr=Heap to see only heap operations.
# - Filter by transaction id with --xid=NNN to follow one transaction.
