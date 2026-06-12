#!/bin/bash

# ============================================================
#  2-upgrade-to-master-master.sh — Fase 2: Promoción a Master-Master
#  Arquitectura Multi-Máquina (LAN)
#
#  Prerrequisito: Haber ejecutado 1-setup-master-slave.sh
#
#  Este script:
#  1. Verifica que la replicación Fase 1 esté activa y sana
#  2. Desactiva read_only en PC2 (lo promueve a Master)
#  3. Configura PC1 para replicar desde PC2 (cierra el ciclo)
#  4. Verifica la replicación bidireccional
#
#  Ejecutar desde cualquier máquina con acceso LAN a ambos
#  nodos y con mysql-client instalado.
# ============================================================

set -euo pipefail

# ── Cargar variables de entorno ────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/.env" ]; then
    export $(grep -v '^#' "$SCRIPT_DIR/.env" | xargs)
else
    echo "ERROR: No se encontró el archivo .env en $SCRIPT_DIR"
    echo "Copia .env.example a .env y configura las IPs de tu red LAN."
    exit 1
fi

# ── Validar variables requeridas ───────────────────────────
if [ -z "${MASTER1_IP:-}" ] || [ -z "${MASTER2_IP:-}" ]; then
    echo "ERROR: Las variables MASTER1_IP y MASTER2_IP deben estar definidas en .env"
    exit 1
fi

MYSQL_PORT="${MYSQL_PORT:-3306}"
ROOT_PASS="${MYSQL_ROOT_PASSWORD:-rootpassword}"

echo "============================================"
echo " Fase 2: Promoción a Master ↔ Master (LAN)"
echo " Master1 (PC1): $MASTER1_IP:$MYSQL_PORT"
echo " Master2 (PC2): $MASTER2_IP:$MYSQL_PORT"
echo "============================================"
echo ""

# ── Paso 1: Verificar que Fase 1 esté activa ──────────────
echo "1️⃣  Verificando que la replicación Fase 1 esté activa en PC2..."

IO_RUNNING=$(mysql -h "$MASTER2_IP" -P "$MYSQL_PORT" -uroot -p"$ROOT_PASS" -N -e \
    "SHOW REPLICA STATUS\G" 2>/dev/null | grep "Replica_IO_Running:" | awk '{print $2}')
SQL_RUNNING=$(mysql -h "$MASTER2_IP" -P "$MYSQL_PORT" -uroot -p"$ROOT_PASS" -N -e \
    "SHOW REPLICA STATUS\G" 2>/dev/null | grep "Replica_SQL_Running:" | awk '{print $2}')

if [ "$IO_RUNNING" != "Yes" ] || [ "$SQL_RUNNING" != "Yes" ]; then
    echo "   ❌ ERROR: La replicación en PC2 no está activa."
    echo "      Replica_IO_Running: $IO_RUNNING"
    echo "      Replica_SQL_Running: $SQL_RUNNING"
    echo ""
    echo "   Ejecuta primero: ./1-setup-master-slave.sh"
    exit 1
fi
echo "   ✅ Replicación Fase 1 verificada (PC2 replica desde PC1)."

# ── Paso 2: Desactivar modo de solo lectura en PC2 ────────
echo "2️⃣  Desactivando modo de solo lectura en PC2..."
mysql -h "$MASTER2_IP" -P "$MYSQL_PORT" -uroot -p"$ROOT_PASS" -e "
SET GLOBAL super_read_only = OFF;
SET GLOBAL read_only = OFF;
" 2>/dev/null

# Verificar
READ_ONLY=$(mysql -h "$MASTER2_IP" -P "$MYSQL_PORT" -uroot -p"$ROOT_PASS" -N -e \
    "SELECT @@global.read_only;" 2>/dev/null)
SUPER_READ_ONLY=$(mysql -h "$MASTER2_IP" -P "$MYSQL_PORT" -uroot -p"$ROOT_PASS" -N -e \
    "SELECT @@global.super_read_only;" 2>/dev/null)

if [ "$READ_ONLY" = "0" ] && [ "$SUPER_READ_ONLY" = "0" ]; then
    echo "   ✅ PC2 ahora acepta escrituras (read_only=OFF, super_read_only=OFF)."
else
    echo "   ❌ ERROR: No se pudo desactivar el modo de solo lectura en PC2."
    echo "      read_only=$READ_ONLY, super_read_only=$SUPER_READ_ONLY"
    exit 1
fi

# ── Paso 3: Verificar usuario replicador en PC2 ───────────
echo "3️⃣  Verificando usuario de replicación en PC2..."
mysql -h "$MASTER2_IP" -P "$MYSQL_PORT" -uroot -p"$ROOT_PASS" -e "
SET sql_log_bin = 0;
CREATE USER IF NOT EXISTS 'replicator'@'%' IDENTIFIED BY 'replpassword';
GRANT REPLICATION SLAVE ON *.* TO 'replicator'@'%';
FLUSH PRIVILEGES;
SET sql_log_bin = 1;
" 2>/dev/null
echo "   ✅ Usuario 'replicator' verificado en PC2."

# ── Paso 4: Configurar Master1 (PC1) para replicar desde PC2 ──
echo "4️⃣  Configurando Master1 (PC1) para replicar desde Master2 (PC2)..."
mysql -h "$MASTER1_IP" -P "$MYSQL_PORT" -uroot -p"$ROOT_PASS" -e "
STOP REPLICA;
CHANGE REPLICATION SOURCE TO
  SOURCE_HOST='$MASTER2_IP',
  SOURCE_PORT=$MYSQL_PORT,
  SOURCE_USER='replicator',
  SOURCE_PASSWORD='replpassword',
  SOURCE_AUTO_POSITION=1,
  GET_SOURCE_PUBLIC_KEY=1;
START REPLICA;
" 2>/dev/null
echo "   ✅ Replicación bidireccional configurada."

# ── Paso 5: Esperar sincronización de PC1 ──────────────────
echo "5️⃣  Esperando sincronización de Master1 (PC1)..."
for i in $(seq 1 30); do
    BEHIND=$(mysql -h "$MASTER1_IP" -P "$MYSQL_PORT" -uroot -p"$ROOT_PASS" -N -e \
        "SHOW REPLICA STATUS\G" 2>/dev/null | grep "Seconds_Behind_Source" | awk '{print $2}')
    SQL_RUN=$(mysql -h "$MASTER1_IP" -P "$MYSQL_PORT" -uroot -p"$ROOT_PASS" -N -e \
        "SHOW REPLICA STATUS\G" 2>/dev/null | grep "Replica_SQL_Running:" | awk '{print $2}')

    if [ "$SQL_RUN" = "Yes" ] && [ "$BEHIND" = "0" ]; then
        echo "   ✅ Master1 (PC1) sincronizado con Master2 (PC2)!"
        break
    elif [ "$SQL_RUN" != "Yes" ]; then
        echo "   ❌ ERROR: El hilo SQL de replicación no está corriendo en PC1."
        mysql -h "$MASTER1_IP" -P "$MYSQL_PORT" -uroot -p"$ROOT_PASS" -e \
            "SHOW REPLICA STATUS\G" 2>/dev/null | grep -E "Last.*Error"
        exit 1
    fi
    echo "   ⏳ Sincronizando... (Seconds_Behind_Source: $BEHIND)"
    sleep 2
done

echo ""
echo "============================================"
echo " Estado de la Replicación Bidireccional"
echo "============================================"
echo ""

# Esperar un momento para que los hilos se estabilicen
sleep 3

# ── Mostrar estado de ambos nodos ──────────────────────────
echo "=== Master1 (PC1) — Replica Status ==="
mysql -h "$MASTER1_IP" -P "$MYSQL_PORT" -uroot -p"$ROOT_PASS" -e \
    "SHOW REPLICA STATUS\G" 2>/dev/null | grep -E "Replica_IO_Running|Replica_SQL_Running|Last_Error|Last_IO_Error|Seconds_Behind"

echo ""
echo "=== Master2 (PC2) — Replica Status ==="
mysql -h "$MASTER2_IP" -P "$MYSQL_PORT" -uroot -p"$ROOT_PASS" -e \
    "SHOW REPLICA STATUS\G" 2>/dev/null | grep -E "Replica_IO_Running|Replica_SQL_Running|Last_Error|Last_IO_Error|Seconds_Behind"

echo ""
echo "============================================"
echo " ✅ Fase 2 completada: Master ↔ Master"
echo "============================================"
echo ""
echo "La replicación bidireccional está activa. Puedes probar con:"
echo ""
echo "  # Master1 → Master2"
echo "  mysql -h $MASTER1_IP -P $MYSQL_PORT -uroot -p$ROOT_PASS -e \\"
echo "    \"INSERT INTO demo_db.Categories VALUES(99, 'Test', 'Desde Master1');\""
echo "  mysql -h $MASTER2_IP -P $MYSQL_PORT -uroot -p$ROOT_PASS -e \\"
echo "    \"SELECT * FROM demo_db.Categories WHERE CategoryID = 99;\""
echo ""
echo "  # Master2 → Master1"
echo "  mysql -h $MASTER2_IP -P $MYSQL_PORT -uroot -p$ROOT_PASS -e \\"
echo "    \"INSERT INTO demo_db.Categories VALUES(100, 'Reverse', 'Desde Master2');\""
echo "  mysql -h $MASTER1_IP -P $MYSQL_PORT -uroot -p$ROOT_PASS -e \\"
echo "    \"SELECT * FROM demo_db.Categories WHERE CategoryID = 100;\""
echo ""
echo "⚠️  Nota: Si reinicias el contenedor de PC2, volverá a arrancar en modo"
echo "   read_only (según my.cnf). Deberás ejecutar este script nuevamente."
echo ""
