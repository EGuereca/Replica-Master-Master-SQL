#!/bin/bash

# ============================================================
#  backup.sh — Respaldo automático de ambos Masters vía LAN
#  Usa las variables de entorno MASTER1_IP y MASTER2_IP
#  (pasadas al contenedor desde docker-compose-pc1.yml)
# ============================================================

# Load environment from /etc/environment (set by Docker CMD)
. /etc/environment 2>/dev/null

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="/backups"
LOG_FILE="/logs/backup.log"
PORT="${MYSQL_PORT:-3306}"

echo "[$TIMESTAMP] Starting backup process..." >> "$LOG_FILE"

# Backup Master 1
echo "[$TIMESTAMP] Backing up mysql-master1 ($MASTER1_IP)..." >> "$LOG_FILE"
mysqldump --no-tablespaces -h "$MASTER1_IP" -P "$PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" > "$BACKUP_DIR/master1_$TIMESTAMP.sql"
gzip "$BACKUP_DIR/master1_$TIMESTAMP.sql"
if [ $? -eq 0 ]; then
    echo "[$TIMESTAMP] mysql-master1 backup successful." >> "$LOG_FILE"
else
    echo "[$TIMESTAMP] ERROR: mysql-master1 backup failed." >> "$LOG_FILE"
fi

# Backup Master 2
echo "[$TIMESTAMP] Backing up mysql-master2 ($MASTER2_IP)..." >> "$LOG_FILE"
mysqldump --no-tablespaces -h "$MASTER2_IP" -P "$PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" > "$BACKUP_DIR/master2_$TIMESTAMP.sql"
gzip "$BACKUP_DIR/master2_$TIMESTAMP.sql"
if [ $? -eq 0 ]; then
    echo "[$TIMESTAMP] mysql-master2 backup successful." >> "$LOG_FILE"
else
    echo "[$TIMESTAMP] ERROR: mysql-master2 backup failed." >> "$LOG_FILE"
fi

echo "[$TIMESTAMP] Backup process completed." >> "$LOG_FILE"
