#!/bin/bash

# ============================================================
#  restore.sh — Restaurar un respaldo a un nodo MySQL
#  Uso: ./restore.sh <IP_del_host> <archivo_respaldo.sql.gz>
#  Ejemplo: ./restore.sh 192.168.1.100 /backups/master1_20260609_120000.sql.gz
# ============================================================

# Load environment from /etc/environment (set by Docker CMD)
. /etc/environment 2>/dev/null

if [ "$#" -ne 2 ]; then
    echo "Usage: ./restore.sh <target_host_ip> <backup_file.sql.gz>"
    echo "Example: ./restore.sh 192.168.1.100 /backups/master1_20260609_120000.sql.gz"
    exit 1
fi

TARGET_HOST=$1
BACKUP_FILE=$2
PORT="${MYSQL_PORT:-3306}"

if [ ! -f "$BACKUP_FILE" ]; then
    echo "Error: File $BACKUP_FILE not found!"
    exit 1
fi

echo "Restoring $BACKUP_FILE to $TARGET_HOST:$PORT..."
gunzip -c "$BACKUP_FILE" | mysql -h "$TARGET_HOST" -P "$PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE"

if [ $? -eq 0 ]; then
    echo "Restore successful."
else
    echo "Restore failed."
fi
