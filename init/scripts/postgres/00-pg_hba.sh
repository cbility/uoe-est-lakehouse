#!/bin/bash
set -e

# Allow connections from any IP address
echo "host all all 0.0.0.0/0 md5" >> ${PGDATA}/pg_hba.conf
echo "host all all ::/0 md5" >> ${PGDATA}/pg_hba.conf
