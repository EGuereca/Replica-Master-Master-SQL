#!/bin/bash

# Load environment variables (Docker sets these)
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="/backups"
LOG_FILE="/logs/backup.log"

echo "[$TIMESTAMP] Starting backup process..." >> "$LOG_FILE"

# Backup Master 1
echo "[$TIMESTAMP] Backing up mysql-master1..." >> "$LOG_FILE"
mysqldump -h mysql-master1 -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" > "$BACKUP_DIR/master1_$TIMESTAMP.sql"
gzip "$BACKUP_DIR/master1_$TIMESTAMP.sql"
if [ $? -eq 0 ]; then
    echo "[$TIMESTAMP] mysql-master1 backup successful." >> "$LOG_FILE"
else
    echo "[$TIMESTAMP] ERROR: mysql-master1 backup failed." >> "$LOG_FILE"
fi

# Backup Master 2
echo "[$TIMESTAMP] Backing up mysql-master2..." >> "$LOG_FILE"
mysqldump -h mysql-master2 -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" > "$BACKUP_DIR/master2_$TIMESTAMP.sql"
gzip "$BACKUP_DIR/master2_$TIMESTAMP.sql"
if [ $? -eq 0 ]; then
    echo "[$TIMESTAMP] mysql-master2 backup successful." >> "$LOG_FILE"
else
    echo "[$TIMESTAMP] ERROR: mysql-master2 backup failed." >> "$LOG_FILE"
fi

echo "[$TIMESTAMP] Backup process completed." >> "$LOG_FILE"
