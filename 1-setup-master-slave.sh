#!/bin/bash

# ============================================================
#  1-setup-master-slave.sh — Fase 1: Replicación Master-Slave
#  Arquitectura Multi-Máquina (LAN)
#
#  Configura a PC2 como Slave de solo lectura de PC1 (Master).
#  PC2 arranca con read_only=ON y super_read_only=ON en my.cnf.
#
#  Ejecutar desde cualquier máquina con acceso LAN a ambos
#  nodos y con mysql-client instalado.
#  Las IPs se leen del archivo .env en el directorio actual.
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
echo " Fase 1: Replicación Master → Slave (LAN)"
echo " Master (PC1): $MASTER1_IP:$MYSQL_PORT"
echo " Slave  (PC2): $MASTER2_IP:$MYSQL_PORT"
echo "============================================"
echo ""

# ── Esperar a que ambas bases de datos estén listas ────────
echo "⏳ Esperando a mysql-master1 ($MASTER1_IP)..."
until mysqladmin ping -h "$MASTER1_IP" -P "$MYSQL_PORT" --silent 2>/dev/null; do
    sleep 2
done
echo "   ✅ mysql-master1 está listo."

echo "⏳ Esperando a mysql-master2 ($MASTER2_IP)..."
until mysqladmin ping -h "$MASTER2_IP" -P "$MYSQL_PORT" --silent 2>/dev/null; do
    sleep 2
done
echo "   ✅ mysql-master2 está listo."

# Esperar a que los scripts init.sql terminen de ejecutarse
echo "⏳ Esperando a que los scripts de inicialización finalicen..."
sleep 15

echo ""
echo "🔧 Configurando replicación Master → Slave..."
echo ""

# ── Paso 1: Verificar/crear usuario replicador en Master (PC1) ─
echo "1️⃣  Verificando usuario de replicación en Master (PC1)..."
mysql -h "$MASTER1_IP" -P "$MYSQL_PORT" -uroot -p"$ROOT_PASS" -e "
SET sql_log_bin = 0;
CREATE USER IF NOT EXISTS 'replicator'@'%' IDENTIFIED BY 'replpassword';
GRANT REPLICATION SLAVE ON *.* TO 'replicator'@'%';
FLUSH PRIVILEGES;
SET sql_log_bin = 1;
" 2>/dev/null
echo "   ✅ Usuario 'replicator' verificado en Master (PC1)."

# ── Paso 2: Configurar Slave (PC2) para replicar desde Master (PC1) ─
echo "2️⃣  Configurando Slave (PC2) para replicar desde Master (PC1)..."
mysql -h "$MASTER2_IP" -P "$MYSQL_PORT" -uroot -p"$ROOT_PASS" -e "
STOP REPLICA;
CHANGE REPLICATION SOURCE TO
  SOURCE_HOST='$MASTER1_IP',
  SOURCE_PORT=$MYSQL_PORT,
  SOURCE_USER='replicator',
  SOURCE_PASSWORD='replpassword',
  SOURCE_AUTO_POSITION=1,
  GET_SOURCE_PUBLIC_KEY=1;
START REPLICA;
" 2>/dev/null
echo "   ✅ Replicación configurada."

# ── Paso 3: Esperar sincronización completa ────────────────
echo "3️⃣  Esperando sincronización del Slave (PC2)..."
for i in $(seq 1 30); do
    BEHIND=$(mysql -h "$MASTER2_IP" -P "$MYSQL_PORT" -uroot -p"$ROOT_PASS" -N -e \
        "SHOW REPLICA STATUS\G" 2>/dev/null | grep "Seconds_Behind_Source" | awk '{print $2}')
    SQL_RUNNING=$(mysql -h "$MASTER2_IP" -P "$MYSQL_PORT" -uroot -p"$ROOT_PASS" -N -e \
        "SHOW REPLICA STATUS\G" 2>/dev/null | grep "Replica_SQL_Running:" | awk '{print $2}')

    if [ "$SQL_RUNNING" = "Yes" ] && [ "$BEHIND" = "0" ]; then
        echo "   ✅ Slave (PC2) completamente sincronizado!"
        break
    elif [ "$SQL_RUNNING" != "Yes" ]; then
        echo "   ❌ ERROR: El hilo SQL de replicación no está corriendo en Slave (PC2)."
        mysql -h "$MASTER2_IP" -P "$MYSQL_PORT" -uroot -p"$ROOT_PASS" -e \
            "SHOW REPLICA STATUS\G" 2>/dev/null | grep -E "Last.*Error"
        exit 1
    fi
    echo "   ⏳ Sincronizando... (Seconds_Behind_Source: $BEHIND)"
    sleep 2
done

# ── Paso 4: Verificar modo de solo lectura en Slave (PC2) ──
echo "4️⃣  Verificando modo de solo lectura en Slave (PC2)..."
READ_ONLY=$(mysql -h "$MASTER2_IP" -P "$MYSQL_PORT" -uroot -p"$ROOT_PASS" -N -e \
    "SELECT @@global.read_only;" 2>/dev/null)
SUPER_READ_ONLY=$(mysql -h "$MASTER2_IP" -P "$MYSQL_PORT" -uroot -p"$ROOT_PASS" -N -e \
    "SELECT @@global.super_read_only;" 2>/dev/null)

if [ "$READ_ONLY" = "1" ] && [ "$SUPER_READ_ONLY" = "1" ]; then
    echo "   ✅ Slave (PC2) está en modo solo lectura (read_only=ON, super_read_only=ON)."
else
    echo "   ⚠️  ADVERTENCIA: Slave (PC2) NO está en modo solo lectura."
    echo "      read_only=$READ_ONLY, super_read_only=$SUPER_READ_ONLY"
    echo "      Verifica que mysql-master2/my.cnf incluya read_only=ON y super_read_only=ON."
fi

echo ""
echo "============================================"
echo " Estado de la Replicación"
echo "============================================"
echo ""

# ── Mostrar estado del Slave ───────────────────────────────
echo "=== Slave (PC2) — Replica Status ==="
mysql -h "$MASTER2_IP" -P "$MYSQL_PORT" -uroot -p"$ROOT_PASS" -e \
    "SHOW REPLICA STATUS\G" 2>/dev/null | grep -E "Replica_IO_Running|Replica_SQL_Running|Last_Error|Last_IO_Error|Seconds_Behind"

# ── Verificar tablas replicadas ────────────────────────────
echo ""
echo "=== Verificación: Tablas replicadas en Slave (PC2) ==="
mysql -h "$MASTER2_IP" -P "$MYSQL_PORT" -uroot -p"$ROOT_PASS" -e \
    "SHOW TABLES FROM demo_db;" 2>/dev/null

echo ""
echo "============================================"
echo " ✅ Fase 1 completada: Master → Slave"
echo "============================================"
echo ""
echo "Puedes probar la replicación unidireccional con:"
echo ""
echo "  # Insertar en Master (PC1) → debe replicarse al Slave (PC2)"
echo "  mysql -h $MASTER1_IP -P $MYSQL_PORT -uroot -p$ROOT_PASS -e \\"
echo "    \"INSERT INTO demo_db.Categories VALUES(99, 'Test', 'Desde Master');\""
echo ""
echo "  # Verificar en Slave (PC2)"
echo "  mysql -h $MASTER2_IP -P $MYSQL_PORT -uroot -p$ROOT_PASS -e \\"
echo "    \"SELECT * FROM demo_db.Categories WHERE CategoryID = 99;\""
echo ""
echo "  # Intentar escribir en Slave (PC2) → debe FALLAR (read_only)"
echo "  mysql -h $MASTER2_IP -P $MYSQL_PORT -uroot -p$ROOT_PASS -e \\"
echo "    \"INSERT INTO demo_db.Categories VALUES(100, 'Fail', 'No debe funcionar');\""
echo ""
echo "Cuando estés listo para activar la replicación bidireccional, ejecuta:"
echo "  ./2-upgrade-to-master-master.sh"
echo ""
