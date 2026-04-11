#!/bin/bash
set -e

BACKUP_DIR=/apps/matrix/db-backup
DATE=$(date +%Y-%m-%d_%H-%M)
FILENAME="synapse_${DATE}.dump"
HC_URL="{{ matrix_db_healthcheck_url }}"

# Ping start
curl -fsS --retry 3 "${HC_URL}/start" > /dev/null

# Run backup — on any failure, ping /fail then exit
if ! docker exec matrix-db \
            pg_dump -U synapse -Fc \
                --exclude-table-data=e2e_one_time_keys_json \
                    synapse > "${BACKUP_DIR}/${FILENAME}"; then
    curl -fsS --retry 3 "${HC_URL}/fail" > /dev/null
        exit 1
fi

# Keep last 7 backups
find "$BACKUP_DIR" -name "synapse_*.dump" -mtime +7 -delete

# Ping success
curl -fsS --retry 3 "${HC_URL}" > /dev/null
echo "Backup complete: ${FILENAME}"
