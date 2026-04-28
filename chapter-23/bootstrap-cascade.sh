#!/bin/sh
# Bootstrap the cascading replica. If $PGDATA is empty, take a base
# backup from the standby (not the primary). Once running, this replica
# streams WAL from the standby and is invisible to the primary's
# pg_stat_replication.

set -e

PGDATA="${PGDATA:-/var/lib/postgresql/data}"

if [ -z "$(ls -A "$PGDATA" 2>/dev/null)" ]; then
    echo "[bootstrap-cascade] empty data dir, running pg_basebackup from $PARENT_HOST"

    until PGPASSWORD="$REPLICATION_PASSWORD" psql \
            -h "$PARENT_HOST" \
            -U "$REPLICATION_USER" \
            -d postgres \
            -c "SELECT 1" >/dev/null 2>&1; do
        echo "[bootstrap-cascade] waiting for parent standby..."
        sleep 2
    done

    # Create a slot on the parent standby for this leaf.
    PGPASSWORD="$REPLICATION_PASSWORD" psql \
        -h "$PARENT_HOST" \
        -U "$REPLICATION_USER" \
        -d postgres \
        -c "SELECT pg_create_physical_replication_slot('cascade_1')
            WHERE NOT EXISTS (
                SELECT 1 FROM pg_replication_slots WHERE slot_name = 'cascade_1'
            );"

    # --wal-method=stream from a parent standby requires max_wal_senders > 0
    # on the parent itself. The walsender that serves this base backup runs
    # on the parent standby, not on the primary.
    PGPASSWORD="$REPLICATION_PASSWORD" pg_basebackup \
        --host="$PARENT_HOST" \
        --username="$REPLICATION_USER" \
        --pgdata="$PGDATA" \
        --wal-method=stream \
        --progress \
        --write-recovery-conf \
        --slot=cascade_1 \
        --no-password

    cat >> "$PGDATA/postgresql.auto.conf" <<EOF
primary_conninfo = 'host=$PARENT_HOST user=$REPLICATION_USER password=$REPLICATION_PASSWORD application_name=cascade_1'
primary_slot_name = 'cascade_1'
hot_standby = on
hot_standby_feedback = on
EOF

    # This script runs as root via the docker entrypoint override, so the
    # chown is meaningful: pg_basebackup ran as root and the postgres
    # process needs ownership of $PGDATA before exec docker-entrypoint.sh.
    chown -R postgres:postgres "$PGDATA"
    chmod 700 "$PGDATA"
fi

exec docker-entrypoint.sh postgres
