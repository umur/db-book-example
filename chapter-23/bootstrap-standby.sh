#!/bin/sh
# Bootstrap the direct standby. If $PGDATA is empty, run pg_basebackup
# from the primary; otherwise hand off to the normal Postgres entrypoint.

set -e

PGDATA="${PGDATA:-/var/lib/postgresql/data}"

if [ -z "$(ls -A "$PGDATA" 2>/dev/null)" ]; then
    echo "[bootstrap-standby] empty data dir, running pg_basebackup from $PRIMARY_HOST"

    # Wait for the primary to accept replication connections.
    until PGPASSWORD="$REPLICATION_PASSWORD" psql \
            -h "$PRIMARY_HOST" \
            -U "$REPLICATION_USER" \
            -d postgres \
            -c "SELECT 1" >/dev/null 2>&1; do
        echo "[bootstrap-standby] waiting for primary..."
        sleep 2
    done

    # Make sure the primary's pg_hba allows our replication user.
    # The primary's image trusts internal connections by default in this
    # sandbox, so no extra step is needed here.

    PGPASSWORD="$REPLICATION_PASSWORD" pg_basebackup \
        --host="$PRIMARY_HOST" \
        --username="$REPLICATION_USER" \
        --pgdata="$PGDATA" \
        --wal-method=stream \
        --progress \
        --write-recovery-conf \
        --slot=standby_1 \
        --no-password

    # The recovery conf written by pg_basebackup uses the connection
    # string we just used; replace the application_name so it shows up
    # cleanly in pg_stat_replication.
    cat >> "$PGDATA/postgresql.auto.conf" <<EOF
primary_conninfo = 'host=$PRIMARY_HOST user=$REPLICATION_USER password=$REPLICATION_PASSWORD application_name=standby_1'
primary_slot_name = 'standby_1'
hot_standby = on
hot_standby_feedback = on
EOF

    # This script runs as root via the docker entrypoint override, so the
    # chown is meaningful: pg_basebackup ran as root and the postgres
    # process needs ownership of $PGDATA before exec docker-entrypoint.sh.
    chown -R postgres:postgres "$PGDATA"
    chmod 700 "$PGDATA"
fi

# Hand off to the upstream entrypoint.
exec docker-entrypoint.sh postgres
