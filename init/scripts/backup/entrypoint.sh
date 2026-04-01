#!/bin/sh
set -e

# Install PostgreSQL client tools
echo "Installing PostgreSQL client..."
apk add --no-cache postgresql17-client

# Create crontab for daily backup at 3am
echo "0 3 * * * /scripts/backup.sh >> /var/log/backup.log 2>&1" > /etc/crontabs/root

# Make scripts executable
chmod +x /scripts/backup.sh

# Create log file
touch /var/log/backup.log

echo "Backup service initialized. Running daily at 3am UTC."
echo "Performing initial backup..."

# Run initial backup
/scripts/backup.sh

echo "Initial backup complete. Starting cron daemon..."

# Start crond in foreground
crond -f -l 2
