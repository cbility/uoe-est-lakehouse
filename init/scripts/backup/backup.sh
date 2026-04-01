#!/bin/sh
set -e

BACKUP_FILE="/backups/uoe_est_lake_catalog.backup.sql"
TEMP_FILE="/backups/uoe_est_lake_catalog.backup.sql.tmp"

echo "[$(date)] Starting PostgreSQL backup..."

PGPASSWORD="${POSTGRES_PASSWORD}" pg_dump \
  -h postgres \
  -U "${POSTGRES_USER}" \
  -d "${POSTGRES_DB}" \
  --no-owner \
  --no-privileges \
  > "${TEMP_FILE}"

# Atomic rename to avoid partial backups
mv "${TEMP_FILE}" "${BACKUP_FILE}"

echo "[$(date)] Backup complete: $(du -h ${BACKUP_FILE} | cut -f1)"
