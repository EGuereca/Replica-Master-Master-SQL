# 🔄 Replicación MySQL con Docker — Despliegue Progresivo (Multi-Máquina LAN)

Sistema de bases de datos MySQL dockerizado y distribuido en **dos computadoras físicas** dentro de la misma red local (LAN). El despliegue es **progresivo en dos fases**: primero se configura una topología **Master-Slave** para testeo, y luego se promueve a **Master-Master** bidireccional. Incluye un servidor de respaldos automáticos.

---

## 📋 Tabla de Contenidos

- [Arquitectura](#-arquitectura)
- [Estructura del Proyecto](#-estructura-del-proyecto)
- [Requisitos Previos](#-requisitos-previos)
- [Configuración de Red y Firewall](#-configuración-de-red-y-firewall)
- [Inicio Rápido](#-inicio-rápido)
- [Configuración Detallada](#-configuración-detallada)
- [Servidor de Respaldos](#-servidor-de-respaldos)
- [Verificación y Pruebas](#-verificación-y-pruebas)
- [Conexión a las Bases de Datos](#-conexión-a-las-bases-de-datos)
- [Comandos Útiles](#-comandos-útiles)
- [Solución de Problemas](#-solución-de-problemas)

---

## 🏗 Arquitectura

### Fase 1: Master → Slave (Replicación Unidireccional)

```
         Red Local (LAN) — ej. 192.168.1.0/24
┌──────────────────────────────┐     ┌──────────────────────────────┐
│         PC1 (MASTER1_IP)     │     │         PC2 (MASTER2_IP)     │
│        ej. 192.168.1.100     │     │        ej. 192.168.1.101     │
│                              │     │                              │
│  ┌──────────────────────┐    │     │    ┌──────────────────────┐  │
│  │   mysql-master1      │    │     │    │   mysql-master2      │  │
│  │   server-id=1        │────┼─────┼──▶│   server-id=2        │  │
│  │   MASTER (R/W)       │    │     │    │   SLAVE (read_only)  │  │
│  │   Puerto: 3306       │    │     │    │   Puerto: 3306       │  │
│  └──────────┬───────────┘    │     │    └──────────────────────┘  │
│             │                │     │                              │
│  ┌──────────▼───────────┐    │     │                              │
│  │   backup-server      │────┼─────┼───▶ (respaldo de ambos)    │
│  │   (cron cada 5 min)  │    │     │                              │
│  └──────────────────────┘    │     │                              │
│                              │     │                              │
│  docker-compose-pc1.yml      │     │  docker-compose-pc2.yml      │
└──────────────────────────────┘     └──────────────────────────────┘
```

### Fase 2: Master ↔ Master (Replicación Bidireccional)

```
         Red Local (LAN) — ej. 192.168.1.0/24
┌──────────────────────────────┐     ┌──────────────────────────────┐
│         PC1 (MASTER1_IP)     │     │         PC2 (MASTER2_IP)     │
│        ej. 192.168.1.100     │     │        ej. 192.168.1.101     │
│                              │     │                              │
│  ┌──────────────────────┐    │     │    ┌──────────────────────┐  │
│  │   mysql-master1      │    │     │    │   mysql-master2      │  │
│  │   server-id=1        │◀──┼─────┼──▶│   server-id=2        │  │
│  │   MASTER (R/W)       │    │     │    │   MASTER (R/W)       │  │
│  │   Puerto: 3306       │    │     │    │   Puerto: 3306       │  │
│  └──────────┬───────────┘    │     │    └──────────────────────┘  │
│             │                │     │                              │
│  ┌──────────▼───────────┐    │     │                              │
│  │   backup-server      │────┼─────┼───▶ (respaldo de ambos)    │
│  │   (cron cada 5 min)  │    │     │                              │
│  └──────────────────────┘    │     │                              │
│                              │     │                              │
│  docker-compose-pc1.yml      │     │  docker-compose-pc2.yml      │
└──────────────────────────────┘     └──────────────────────────────┘
```

**¿Cómo funciona el despliegue progresivo?**

1. **Fase 1 — Master-Slave:** PC1 es el Master con escrituras y lecturas. PC2 es un Slave de solo lectura (`read_only=ON`, `super_read_only=ON`). Los datos se replican unidireccionalmente de PC1 → PC2 usando GTID. Esto permite **testear** la replicación antes de activar la bidireccional.

2. **Fase 2 — Master-Master:** Se desactiva el modo solo lectura en PC2 y se configura PC1 para replicar desde PC2, cerrando el ciclo bidireccional. Ambos nodos aceptan escrituras.

3. **Backup-server** (en PC1) ejecuta `mysqldump` cada 5 minutos contra ambos nodos vía sus IPs LAN, independientemente de la fase activa.

---

## 📁 Estructura del Proyecto

```
Proyecto/
├── docker-compose-pc1.yml        # Orquestación para PC1 (Master + backup-server)
├── docker-compose-pc2.yml        # Orquestación para PC2 (Slave → Master)
├── 1-setup-master-slave.sh       # Fase 1: Configura replicación Master → Slave
├── 2-upgrade-to-master-master.sh # Fase 2: Promueve a Master ↔ Master
├── setup-replication.sh          # (Referencia) Script original Master-Master directo
├── .env                          # Variables de entorno: credenciales + IPs LAN
├── .env.master2                  # Variables para PC2 (solo root password)
├── .env.example                  # Plantilla de ejemplo para .env
├── .gitignore                    # Excluye .env, backups/ y logs/
├── Northwind.sql                 # Esquema y datos originales de referencia
│
├── mysql-master1/
│   ├── my.cnf                    # Config MySQL: server-id=1, GTID, binlog
│   └── init.sql                  # Inicialización: usuario replicador + esquema Northwind
│
├── mysql-master2/
│   ├── my.cnf                    # Config MySQL: server-id=2, GTID, read_only=ON
│   └── init.sql                  # Solo crea el usuario replicador
│
├── backup-server/
│   ├── Dockerfile                # Imagen con mysql-client y cron
│   ├── backup.sh                 # Script de respaldo (mysqldump vía IPs LAN)
│   ├── restore.sh                # Restauración desde archivo .sql.gz
│   └── crontab                   # Programación cron (cada 5 minutos)
│
├── backups/                      # Respaldos generados (volumen montado)
├── logs/                         # Logs del servidor de respaldos
└── docs/
    └── Manual_de_Uso.md          # Manual de uso detallado
```

### Archivos Clave

| Archivo | Descripción |
|---------|-------------|
| `1-setup-master-slave.sh` | **Fase 1:** Configura la replicación unidireccional PC1 → PC2 (Slave read_only) |
| `2-upgrade-to-master-master.sh` | **Fase 2:** Desactiva read_only en PC2 y cierra el ciclo bidireccional |
| `docker-compose-pc1.yml` | Servicios de PC1: `mysql-master1` + `backup-server`, puerto 3306 |
| `docker-compose-pc2.yml` | Servicio de PC2: `mysql-master2`, puerto 3306 |
| `mysql-master1/my.cnf` | Binary log, GTID, `log_slave_updates`, `bind-address=0.0.0.0` |
| `mysql-master2/my.cnf` | Igual que Master1 pero `server-id=2` + `read_only=ON` + `super_read_only=ON` |
| `mysql-master1/init.sql` | Crea usuario `replicator`, tablas Northwind e inserta datos |
| `mysql-master2/init.sql` | Solo crea el usuario `replicator` (datos llegan vía replicación) |
| `.env` | Credenciales MySQL + IPs LAN (`MASTER1_IP`, `MASTER2_IP`, `MYSQL_PORT`) |
| `setup-replication.sh` | Script original de referencia (configura Master-Master en un solo paso) |

---

## ✅ Requisitos Previos

- **Docker** (20.10+) — instalado en **ambas** computadoras (PC1 y PC2)
- **Docker Compose** (v2+) — instalado en **ambas** computadoras
- **Bash** (para ejecutar los scripts de replicación)
- **mysql-client** — instalado en la máquina desde donde se ejecuten los scripts
- **Red LAN** — ambas computadoras deben estar en la misma red local
- Permisos de `sudo` para ejecutar comandos Docker (o usuario en el grupo `docker`)

### Instalar mysql-client

```bash
# Debian / Ubuntu
sudo apt-get install -y default-mysql-client

# CentOS / RHEL / Fedora
sudo dnf install -y mysql
```

---

## 🔒 Configuración de Red y Firewall

> ⚠️ **IMPORTANTE:** El puerto **3306** debe estar **abierto en el firewall** de ambas computadoras físicas para permitir el tráfico MySQL entrante desde la LAN. Sin esto, la replicación y los respaldos no funcionarán.

### Opción A: UFW (Ubuntu / Debian)

```bash
sudo ufw allow from 192.168.1.0/24 to any port 3306 proto tcp
sudo ufw status verbose
```

### Opción B: firewalld (CentOS / RHEL / Fedora)

```bash
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.1.0/24" port protocol="tcp" port="3306" accept'
sudo firewall-cmd --reload
```

### Opción C: iptables (manual)

```bash
sudo iptables -A INPUT -p tcp --dport 3306 -s 192.168.1.0/24 -j ACCEPT
sudo iptables-save > /etc/iptables/rules.v4
```

### Verificar conectividad entre PCs

```bash
# Desde PC1, verificar que se alcanza PC2
ping 192.168.1.101

# Desde PC2, verificar que se alcanza PC1
ping 192.168.1.100
```

---

## 🚀 Inicio Rápido

### 1. Clonar el repositorio en ambas PCs

```bash
# En PC1 y PC2
git clone <URL_DEL_REPOSITORIO>
cd Proyecto
```

### 2. Configurar las variables de entorno

En **PC1**, copia y edita el archivo `.env`:

```bash
cp .env.example .env
```

Edita `.env` con las IPs reales de tu red LAN:

```env
MYSQL_ROOT_PASSWORD=rootpassword
MYSQL_DATABASE=demo_db
MYSQL_USER=demouser
MYSQL_PASSWORD=demopassword

# --- Configuración de Red LAN ---
MASTER1_IP=192.168.1.100    # ← IP real de PC1
MASTER2_IP=192.168.1.101    # ← IP real de PC2
MYSQL_PORT=3306
```

> **Nota:** El archivo `.env.master2` ya viene incluido en PC2 y solo contiene `MYSQL_ROOT_PASSWORD`.

### 3. Levantar los contenedores

**En PC1** (Master + backup-server):

```bash
sudo docker compose -f docker-compose-pc1.yml up -d --build
```

**En PC2** (Slave):

```bash
sudo docker compose -f docker-compose-pc2.yml up -d --build
```

### 4. Fase 1 — Configurar replicación Master → Slave

Desde **PC1** (o cualquier máquina con acceso LAN y `mysql-client`):

```bash
./1-setup-master-slave.sh
```

El script:
1. Espera a que ambas bases de datos estén accesibles
2. Verifica el usuario de replicación en PC1
3. Configura PC2 como réplica de PC1 (recibe esquema y datos)
4. Espera sincronización completa
5. Verifica que PC2 esté en modo solo lectura

**Salida esperada:**

```
Replica_IO_Running: Yes
Replica_SQL_Running: Yes
Seconds_Behind_Source: 0
```

### 5. Probar la replicación unidireccional

```bash
# Insertar en Master (PC1) → debe replicarse al Slave
mysql -h 192.168.1.100 -P 3306 -uroot -prootpassword -e \
  "INSERT INTO demo_db.Categories VALUES(99, 'Test', 'Desde Master');"

# Verificar en Slave (PC2)
mysql -h 192.168.1.101 -P 3306 -uroot -prootpassword -e \
  "SELECT * FROM demo_db.Categories WHERE CategoryID = 99;"

# Intentar escribir en Slave (PC2) → debe FALLAR
mysql -h 192.168.1.101 -P 3306 -uroot -prootpassword -e \
  "INSERT INTO demo_db.Categories VALUES(100, 'Fail', 'No debe funcionar');"
# Error esperado: The MySQL server is running with the --super-read-only option
```

### 6. Fase 2 — Promoción a Master ↔ Master

Cuando la Fase 1 esté verificada:

```bash
./2-upgrade-to-master-master.sh
```

El script:
1. Verifica que la replicación Fase 1 esté activa y sana
2. Desactiva `read_only` y `super_read_only` en PC2
3. Configura PC1 para replicar desde PC2 (cierra el ciclo)
4. Verifica la replicación bidireccional

### 7. ¡Listo! Verificar la sincronización bidireccional

```bash
# Master1 → Master2
mysql -h 192.168.1.100 -P 3306 -uroot -prootpassword -e \
  "INSERT INTO demo_db.Categories VALUES(99, 'Test', 'Desde Master1');"
mysql -h 192.168.1.101 -P 3306 -uroot -prootpassword -e \
  "SELECT * FROM demo_db.Categories WHERE CategoryID = 99;"

# Master2 → Master1
mysql -h 192.168.1.101 -P 3306 -uroot -prootpassword -e \
  "INSERT INTO demo_db.Categories VALUES(100, 'Reverse', 'Desde Master2');"
mysql -h 192.168.1.100 -P 3306 -uroot -prootpassword -e \
  "SELECT * FROM demo_db.Categories WHERE CategoryID = 100;"
```

---

## ⚙ Configuración Detallada

### Configuración MySQL (`my.cnf`)

#### Master1 (PC1) — `mysql-master1/my.cnf`

```ini
[mysqld]
server-id=1
log_bin=mysql-bin
gtid_mode=ON
enforce_gtid_consistency=ON
log_slave_updates=ON
binlog_format=ROW
bind-address=0.0.0.0
```

#### Master2/Slave (PC2) — `mysql-master2/my.cnf`

```ini
[mysqld]
server-id=2
log_bin=mysql-bin
gtid_mode=ON
enforce_gtid_consistency=ON
log_slave_updates=ON
binlog_format=ROW
bind-address=0.0.0.0
read_only=ON
super_read_only=ON
```

#### ¿Por qué cada parámetro?

| Parámetro | Propósito |
|-----------|-----------|
| `gtid_mode=ON` | Cada transacción tiene un ID único global, facilitando la sincronización |
| `log_slave_updates=ON` | Los cambios recibidos por replicación se escriben al binlog propio |
| `binlog_format=ROW` | Replica los datos exactos modificados (más seguro que sentencias SQL) |
| `bind-address=0.0.0.0` | MySQL acepta conexiones desde cualquier interfaz de red |
| `read_only=ON` | (Solo PC2) Bloquea escrituras de usuarios sin privilegio SUPER |
| `super_read_only=ON` | (Solo PC2) Bloquea escrituras incluso de usuarios con SUPER |

> **Nota sobre `read_only` y `super_read_only`:** Están configurados en `my.cnf` de PC2 para que el nodo **siempre arranque en modo Slave**. En la Fase 2, se desactivan dinámicamente con `SET GLOBAL` sin reiniciar el contenedor. Si el contenedor se reinicia, volverá a modo solo lectura y se deberá ejecutar `2-upgrade-to-master-master.sh` nuevamente.

### Archivo `.env` — Variables de Entorno

```env
MYSQL_ROOT_PASSWORD=rootpassword
MYSQL_DATABASE=demo_db
MYSQL_USER=demouser
MYSQL_PASSWORD=demopassword

MASTER1_IP=192.168.1.100
MASTER2_IP=192.168.1.101
MYSQL_PORT=3306
```

### ¿Por qué Master2 tiene un `.env` diferente?

Master2 usa `.env.master2` (solo `MYSQL_ROOT_PASSWORD`) porque:

- El entrypoint de Docker MySQL crea automáticamente la base de datos y usuario al iniciar.
- Si ambos servidores crean los mismos objetos, se generan **conflictos de GTID**.
- La base de datos `demo_db` y el usuario `demouser` se crean **únicamente en Master1** y llegan a PC2 vía replicación.

### Datos Iniciales

El esquema **Northwind** se carga automáticamente en Master1 al iniciar (`mysql-master1/init.sql`). Incluye: `Categories`, `Customers`, `Employees`, `Shippers`, `Suppliers`, `Products`, `Orders`, `OrderDetails`.

---

## 💾 Servidor de Respaldos

### Funcionamiento

El contenedor `backup-server` (en PC1) ejecuta un **cron job** cada 5 minutos que:

1. Realiza `mysqldump` contra **ambos** nodos usando sus IPs LAN
2. Comprime cada respaldo con `gzip`
3. Almacena los archivos en `backups/` del host (PC1)
4. Registra logs en `logs/backup.log`

> **Nota:** Los respaldos funcionan en **ambas fases**. `mysqldump` es una operación de lectura, por lo que no tiene problemas con el modo `read_only` de PC2 en la Fase 1.

### Archivos generados

```
backups/
├── master1_20260609_120000.sql.gz
├── master1_20260609_120500.sql.gz
├── master2_20260609_120000.sql.gz
└── master2_20260609_120500.sql.gz
```

### Restaurar un respaldo

```bash
sudo docker exec backup-server /restore.sh <IP_del_host> <archivo_respaldo>
```

**Ejemplo:**

```bash
sudo docker exec backup-server /restore.sh 192.168.1.100 /backups/master1_20260609_120000.sql.gz
```

### Ver los logs de respaldo

```bash
cat logs/backup.log
```

---

## 🔍 Verificación y Pruebas

### Verificar el estado de la replicación

```bash
# Estado en PC2 (Fase 1 y 2: replicando desde PC1)
mysql -h 192.168.1.101 -P 3306 -uroot -prootpassword -e "SHOW REPLICA STATUS\G"

# Estado en PC1 (solo Fase 2: replicando desde PC2)
mysql -h 192.168.1.100 -P 3306 -uroot -prootpassword -e "SHOW REPLICA STATUS\G"
```

**Campos importantes:**

| Campo | Valor esperado | Significado |
|-------|---------------|-------------|
| `Replica_IO_Running` | `Yes` | Hilo de lectura de binlog activo |
| `Replica_SQL_Running` | `Yes` | Hilo de ejecución de SQL activo |
| `Seconds_Behind_Source` | `0` | Sin retraso en la replicación |
| `Last_Error` | (vacío) | Sin errores |

### Verificar modo solo lectura (Fase 1)

```bash
# Debe mostrar 1 (activo) en Fase 1, 0 (inactivo) en Fase 2
mysql -h 192.168.1.101 -P 3306 -uroot -prootpassword -e \
  "SELECT @@global.read_only AS read_only, @@global.super_read_only AS super_read_only;"
```

---

## 🔌 Conexión a las Bases de Datos

### Desde cualquier máquina en la LAN

| Nodo | Host | Puerto | Usuario | Contraseña | Base de datos | Escritura |
|------|------|--------|---------|------------|---------------|-----------|
| Master/PC1 | `192.168.1.100` | `3306` | `demouser` | `demopassword` | `demo_db` | ✅ Siempre |
| Slave-Master/PC2 | `192.168.1.101` | `3306` | `demouser` | `demopassword` | `demo_db` | ❌ Fase 1 / ✅ Fase 2 |

```bash
mysql -h 192.168.1.100 -P 3306 -u demouser -pdemopassword demo_db
```

---

## 🛠 Comandos Útiles

### En PC1

```bash
# Levantar Master + backup-server
sudo docker compose -f docker-compose-pc1.yml up -d --build

# Ver logs del contenedor Master
sudo docker logs mysql-master1

# Acceder a la consola MySQL de Master
sudo docker exec -it mysql-master1 mysql -uroot -prootpassword

# Detener servicios de PC1
sudo docker compose -f docker-compose-pc1.yml down

# Detener y eliminar volúmenes (reinicio limpio)
sudo docker compose -f docker-compose-pc1.yml down -v

# Forzar respaldo manual
sudo docker exec backup-server /backup.sh
```

### En PC2

```bash
# Levantar Slave/Master2
sudo docker compose -f docker-compose-pc2.yml up -d --build

# Ver logs del contenedor
sudo docker logs mysql-master2

# Acceder a la consola MySQL
sudo docker exec -it mysql-master2 mysql -uroot -prootpassword

# Detener servicios de PC2
sudo docker compose -f docker-compose-pc2.yml down

# Detener y eliminar volúmenes (reinicio limpio)
sudo docker compose -f docker-compose-pc2.yml down -v
```

### Desde cualquier máquina con acceso LAN

```bash
# Fase 1: Configurar replicación Master → Slave
./1-setup-master-slave.sh

# Fase 2: Promover a Master ↔ Master
./2-upgrade-to-master-master.sh

# Ver contenedores activos (en cada PC)
sudo docker ps

# Ver respaldos disponibles (en PC1)
ls -lh backups/
```

---

## ❓ Solución de Problemas

### No se puede conectar al otro nodo

1. **Verificar conectividad:** `ping <IP_DEL_OTRO_NODO>`
2. **Verificar puerto 3306:** `nc -zv 192.168.1.101 3306`
3. **Verificar firewall:** `sudo ufw status` o `sudo firewall-cmd --list-all`
4. **Verificar bind-address:** `sudo docker exec mysql-master1 mysql -uroot -prootpassword -e "SHOW VARIABLES LIKE 'bind_address';"`

### `Replica_SQL_Running: No`

```bash
mysql -h <IP_DEL_NODO> -P 3306 -uroot -prootpassword -e "SHOW REPLICA STATUS\G" | grep Error
```

**Solución general:** Reiniciar desde cero:

```bash
# En PC1
sudo docker compose -f docker-compose-pc1.yml down -v
sudo docker compose -f docker-compose-pc1.yml up -d --build

# En PC2
sudo docker compose -f docker-compose-pc2.yml down -v
sudo docker compose -f docker-compose-pc2.yml up -d --build

# Luego reconfigurar
./1-setup-master-slave.sh
# (Opcional) Promover a Master-Master
./2-upgrade-to-master-master.sh
```

### PC2 vuelve a modo solo lectura después de reiniciar

Esto es **comportamiento esperado**. El `my.cnf` de PC2 incluye `read_only=ON` para que siempre arranque como Slave. Después de reiniciar el contenedor:

1. Ejecuta `./1-setup-master-slave.sh` para restaurar la replicación
2. Si necesitas Master-Master, ejecuta `./2-upgrade-to-master-master.sh`

### Las tablas no aparecen en PC2

Verificar que `1-setup-master-slave.sh` se ejecutó después de que los contenedores estuvieran completamente inicializados. El script espera 15 segundos, pero en sistemas lentos puede requerir más tiempo.

### Los respaldos no se generan

```bash
sudo docker logs backup-server
cat logs/cron.log
cat logs/backup.log
```

### Error de permisos con Docker

```bash
sudo usermod -aG docker $USER
# Cerrar sesión y volver a iniciar
```
