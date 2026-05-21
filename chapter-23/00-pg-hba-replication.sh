#!/usr/bin/env bash
# Allow replication connections from any host inside the docker network so the
# standby and cascade pg_basebackup and streaming connections succeed. The
# default pg_hba.conf shipped by the postgres image only permits local
# replication.
set -euo pipefail

cat >> "$PGDATA/pg_hba.conf" <<'HBA'

# Added by chapter-23 sandbox: allow replication from any host on the docker
# network. Use a real CIDR and authentication method in production.
host    replication     all             0.0.0.0/0               trust
host    replication     all             ::/0                    trust
HBA
