#!/bin/bash

if [ "$#" -ne 2 ]; then
    echo "Usage: ./restore.sh <target_host> <backup_file.sql.gz>"
    echo "Example: ./restore.sh mysql-master1 /backups/master1_20231026_120000.sql.gz"
    exit 1
fi

TARGET_HOST=$1
BACKUP_FILE=$2

if [ ! -f "$BACKUP_FILE" ]; then
    echo "Error: File $BACKUP_FILE not found!"
    exit 1
fi

echo "Restoring $BACKUP_FILE to $TARGET_HOST..."
gunzip -c "$BACKUP_FILE" | mysql -h "$TARGET_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE"

if [ $? -eq 0 ]; then
    echo "Restore successful."
else
    echo "Restore failed."
fi
