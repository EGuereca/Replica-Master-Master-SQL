# 🔄 Replicación Master-Master MySQL con Docker (Multi-Máquina LAN)

Sistema de bases de datos MySQL con arquitectura **Master-Master** dockerizado y distribuido en **dos computadoras físicas** dentro de la misma red local (LAN). Ambos nodos funcionan simultáneamente como origen y réplica, permitiendo lecturas y escrituras en cualquiera de los dos. Incluye un servidor de respaldos automáticos.

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

```
         Red Local (LAN) — ej. 192.168.1.0/24
┌──────────────────────────────┐     ┌──────────────────────────────┐
│         PC1 (MASTER1_IP)     │     │         PC2 (MASTER2_IP)     │
│        ej. 192.168.1.100     │     │        ej. 192.168.1.101     │
│                              │     │                              │
│  ┌──────────────────────┐    │     │    ┌──────────────────────┐  │
│  │   mysql-master1      │    │     │    │   mysql-master2      │  │
│  │   server-id=1        │◀──┼─────┼──▶│   server-id=2        │  │
│  │   Puerto: 3306       │    │     │    │   Puerto: 3306       │  │
│  └──────────┬───────────┘    │     │    └──────────────────────┘  │
│             │                │     │                              │
│  ┌──────────▼───────────┐    │     │                              │
│  │   backup-server      │────┼─────┼───▶ (respaldo de master2)   │
│  │   (cron cada 5 min)  │    │     │                              │
│  └──────────────────────┘    │     │                              │
│                              │     │                              │
│  docker-compose-pc1.yml      │     │  docker-compose-pc2.yml      │
└──────────────────────────────┘     └──────────────────────────────┘
```

**¿Cómo funciona?**

- **Master1** (PC1) y **Master2** (PC2) son nodos MySQL 8.0 con replicación bidireccional basada en **GTID** (Global Transaction Identifiers).
- Cada nodo se ejecuta en una **computadora física diferente** dentro de la misma LAN.
- Cualquier escritura (INSERT, UPDATE, DELETE) en un nodo se replica automáticamente al otro a través de la red local.
- El **backup-server** (en PC1) ejecuta `mysqldump` cada 5 minutos contra ambos nodos vía sus IPs LAN y almacena los respaldos comprimidos.
- La comunicación entre nodos utiliza las **IPs reales de la LAN** (no nombres de contenedores Docker).

---

## 📁 Estructura del Proyecto

```
Proyecto/
├── docker-compose-pc1.yml     # Orquestación para PC1 (Master1 + backup-server)
├── docker-compose-pc2.yml     # Orquestación para PC2 (Master2)
├── docker-compose.yml         # (Referencia) Archivo original single-host
├── setup-replication.sh       # Script para configurar la replicación Master-Master
├── .env                       # Variables de entorno: credenciales + IPs de la LAN
├── .env.master2               # Variables de entorno para Master2 (solo root password)
├── .env.example               # Plantilla de ejemplo para .env
├── .gitignore                 # Excluye .env, backups/ y logs/
├── Northwind.sql              # Esquema y datos originales de referencia (Northwind)
│
├── mysql-master1/
│   ├── my.cnf                 # Configuración MySQL: server-id=1, GTID, binlog, bind-address
│   └── init.sql               # Script de inicialización: usuario replicador + esquema Northwind
│
├── mysql-master2/
│   ├── my.cnf                 # Configuración MySQL: server-id=2, GTID, binlog, bind-address
│   └── init.sql               # Script mínimo: solo crea el usuario replicador
│
├── backup-server/
│   ├── Dockerfile             # Imagen basada en Debian con mysql-client y cron
│   ├── backup.sh              # Script de respaldo (mysqldump vía IPs LAN)
│   ├── restore.sh             # Script de restauración desde un archivo .sql.gz
│   └── crontab                # Programación cron (cada 5 minutos)
│
├── backups/                   # Respaldos generados (montado como volumen)
├── logs/                      # Logs del servidor de respaldos
└── docs/
    └── Manual_de_Uso.md       # Manual de uso detallado
```

### Archivos Clave

| Archivo | Descripción |
|---------|-------------|
| `docker-compose-pc1.yml` | Servicios de PC1: `mysql-master1` + `backup-server`, puerto 3306 expuesto al host |
| `docker-compose-pc2.yml` | Servicio de PC2: `mysql-master2`, puerto 3306 expuesto al host |
| `setup-replication.sh` | Configura la replicación bidireccional GTID usando IPs LAN del `.env` |
| `mysql-master1/my.cnf` | Habilita binary log, GTID, `log_slave_updates` y `bind-address=0.0.0.0` en Master1 |
| `mysql-master2/my.cnf` | Misma configuración que Master1 pero con `server-id=2` |
| `mysql-master1/init.sql` | Crea el usuario `replicator`, las tablas de Northwind e inserta datos iniciales |
| `mysql-master2/init.sql` | Solo crea el usuario `replicator` (los datos llegan vía replicación) |
| `.env` | Credenciales de MySQL + IPs de la LAN (`MASTER1_IP`, `MASTER2_IP`, `MYSQL_PORT`) |
| `.env.master2` | Solo el root password (la BD y usuario se crean vía replicación desde Master1) |

---

## ✅ Requisitos Previos

- **Docker** (20.10+) — instalado en **ambas** computadoras (PC1 y PC2)
- **Docker Compose** (v2+) — instalado en **ambas** computadoras
- **Bash** (para ejecutar `setup-replication.sh`)
- **mysql-client** — instalado en la máquina desde donde se ejecute `setup-replication.sh`
- **Red LAN** — ambas computadoras deben estar en la misma red local y poder comunicarse entre sí
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
# Permitir MySQL desde la LAN (ajusta la subred a tu red)
sudo ufw allow from 192.168.1.0/24 to any port 3306 proto tcp

# Verificar las reglas
sudo ufw status verbose

# Si UFW no está activo, habilitarlo:
sudo ufw enable
```

### Opción B: firewalld (CentOS / RHEL / Fedora)

```bash
# Permitir MySQL de forma permanente
sudo firewall-cmd --permanent --add-service=mysql

# O especificar el puerto directamente
sudo firewall-cmd --permanent --add-port=3306/tcp

# Restringir a una subred específica (más seguro)
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.1.0/24" port protocol="tcp" port="3306" accept'

# Recargar las reglas
sudo firewall-cmd --reload

# Verificar
sudo firewall-cmd --list-all
```

### Opción C: iptables (manual)

```bash
# Permitir MySQL desde la subred LAN
sudo iptables -A INPUT -p tcp --dport 3306 -s 192.168.1.0/24 -j ACCEPT

# Guardar las reglas (varía según la distribución)
sudo iptables-save > /etc/iptables/rules.v4
```

### Verificar conectividad entre PCs

Antes de levantar los contenedores, verifica que ambas PCs se comuniquen:

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

> **Nota:** El archivo `.env.master2` ya viene incluido en PC2 y solo contiene `MYSQL_ROOT_PASSWORD`. No es necesario modificarlo.

### 3. Levantar los contenedores

**En PC1** (Master1 + backup-server):

```bash
sudo docker compose -f docker-compose-pc1.yml up -d --build
```

**En PC2** (Master2):

```bash
sudo docker compose -f docker-compose-pc2.yml up -d --build
```

Esto creará y levantará:
- **PC1:** `mysql-master1` en puerto **3306** + `backup-server` (respaldos automáticos)
- **PC2:** `mysql-master2` en puerto **3306**

### 4. Configurar la replicación

Desde **PC1** (o cualquier máquina con acceso LAN y `mysql-client` instalado):

```bash
./setup-replication.sh
```

El script:
1. Lee las IPs de la LAN desde `.env`
2. Espera a que ambas bases de datos estén accesibles vía LAN
3. Configura Master2 como réplica de Master1 (recibe esquema y datos)
4. Espera a que Master2 esté sincronizado
5. Configura Master1 como réplica de Master2 (completando el ciclo)
6. Verifica el estado de la replicación y muestra las tablas en Master2

**Salida esperada:**

```
Replica_IO_Running: Yes
Replica_SQL_Running: Yes
Seconds_Behind_Source: 0
```

### 5. ¡Listo! Verificar la sincronización

```bash
# Insertar en Master1 (desde cualquier máquina con mysql-client)
mysql -h 192.168.1.100 -P 3306 -uroot -prootpassword -e \
  "INSERT INTO demo_db.Categories VALUES(99, 'Test', 'Prueba de sincronización');"

# Verificar en Master2
mysql -h 192.168.1.101 -P 3306 -uroot -prootpassword -e \
  "SELECT * FROM demo_db.Categories WHERE CategoryID = 99;"
```

Si la replicación funciona, verás el registro insertado en Master2.

---

## ⚙ Configuración Detallada

### Configuración MySQL (`my.cnf`)

Ambos nodos comparten la misma configuración (solo difiere el `server-id`):

```ini
[mysqld]
server-id=1                    # 1 para Master1, 2 para Master2
log_bin=mysql-bin              # Habilita el binary log
gtid_mode=ON                   # Identificadores globales de transacción
enforce_gtid_consistency=ON    # Fuerza consistencia GTID
log_slave_updates=ON           # Replica los cambios recibidos al binlog propio
binlog_format=ROW              # Formato de replicación basado en filas
bind-address=0.0.0.0           # Acepta conexiones desde cualquier interfaz (LAN)
```

#### ¿Por qué cada parámetro?

- **`gtid_mode=ON`**: Cada transacción tiene un ID único global, facilitando la sincronización y evitando duplicados.
- **`log_slave_updates=ON`**: Sin esto, los cambios recibidos por replicación no se escriben al binlog, lo que rompe la replicación en sentido inverso.
- **`binlog_format=ROW`**: Replica los datos exactos modificados (más seguro que replicar la sentencia SQL).
- **`bind-address=0.0.0.0`**: Permite que MySQL acepte conexiones desde cualquier interfaz de red, no solo `localhost`. **Indispensable** para la comunicación entre PCs vía LAN.

### Archivo `.env` — Variables de Entorno

```env
# Credenciales MySQL (usadas por Master1 y backup-server)
MYSQL_ROOT_PASSWORD=rootpassword
MYSQL_DATABASE=demo_db
MYSQL_USER=demouser
MYSQL_PASSWORD=demopassword

# Configuración de Red LAN
MASTER1_IP=192.168.1.100      # IP de la PC que ejecuta Master1
MASTER2_IP=192.168.1.101      # IP de la PC que ejecuta Master2
MYSQL_PORT=3306               # Puerto MySQL expuesto en ambos hosts
```

### ¿Por qué Master2 tiene un `.env` diferente?

Master2 usa `.env.master2` (solo `MYSQL_ROOT_PASSWORD`) porque:

- El entrypoint de Docker MySQL crea automáticamente la base de datos (`MYSQL_DATABASE`) y el usuario (`MYSQL_USER`) al iniciar.
- Si ambos servidores crean los mismos objetos, se generan **conflictos de GTID** al intentar replicar (e.g., `CREATE USER` falla porque el usuario ya existe).
- Al omitir estas variables en Master2, la base de datos `demo_db` y el usuario `demouser` se crean **únicamente en Master1** y llegan a Master2 vía replicación.

### Datos Iniciales

El esquema **Northwind** se carga automáticamente en Master1 al iniciar (`mysql-master1/init.sql`). Incluye las tablas:

- `Categories`, `Customers`, `Employees`, `Shippers`, `Suppliers`
- `Products`, `Orders`, `OrderDetails`

---

## 💾 Servidor de Respaldos

### Funcionamiento

El contenedor `backup-server` (en PC1) ejecuta un **cron job** cada 5 minutos que:

1. Realiza `mysqldump` contra **ambos** masters usando sus IPs LAN (`MASTER1_IP` y `MASTER2_IP`)
2. Comprime cada respaldo con `gzip`
3. Almacena los archivos en el directorio `backups/` del host (PC1)
4. Registra logs en `logs/backup.log`

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
# Restaurar en Master1 (PC1)
sudo docker exec backup-server /restore.sh 192.168.1.100 /backups/master1_20260609_120000.sql.gz

# Restaurar en Master2 (PC2)
sudo docker exec backup-server /restore.sh 192.168.1.101 /backups/master2_20260609_120000.sql.gz
```

### Ver los logs de respaldo

```bash
cat logs/backup.log
```

---

## 🔍 Verificación y Pruebas

### Verificar el estado de la replicación

```bash
# Estado en Master1 (replicando desde Master2)
mysql -h 192.168.1.100 -P 3306 -uroot -prootpassword -e "SHOW REPLICA STATUS\G"

# Estado en Master2 (replicando desde Master1)
mysql -h 192.168.1.101 -P 3306 -uroot -prootpassword -e "SHOW REPLICA STATUS\G"
```

**Campos importantes:**

| Campo | Valor esperado | Significado |
|-------|---------------|-------------|
| `Replica_IO_Running` | `Yes` | Hilo de lectura de binlog activo |
| `Replica_SQL_Running` | `Yes` | Hilo de ejecución de SQL activo |
| `Seconds_Behind_Source` | `0` | Sin retraso en la replicación |
| `Last_Error` | (vacío) | Sin errores |

### Probar sincronización bidireccional

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

## 🔌 Conexión a las Bases de Datos

### Desde cualquier máquina en la LAN

| Nodo | Host | Puerto | Usuario | Contraseña | Base de datos |
|------|------|--------|---------|------------|---------------|
| Master1 | `192.168.1.100` (MASTER1_IP) | `3306` | `demouser` | `demopassword` | `demo_db` |
| Master2 | `192.168.1.101` (MASTER2_IP) | `3306` | `demouser` | `demopassword` | `demo_db` |
| Cualquiera (root) | IP del nodo | `3306` | `root` | `rootpassword` | `demo_db` |

**Ejemplo con cliente MySQL:**

```bash
mysql -h 192.168.1.100 -P 3306 -u demouser -pdemopassword demo_db
```

**Ejemplo con DBeaver, MySQL Workbench u otro cliente gráfico:**

Usa la IP LAN del nodo al que deseas conectarte como hostname y el puerto `3306`.

---

## 🛠 Comandos Útiles

### En PC1

```bash
# Levantar Master1 + backup-server
sudo docker compose -f docker-compose-pc1.yml up -d --build

# Ver logs del contenedor Master1
sudo docker logs mysql-master1

# Acceder a la consola MySQL de Master1
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
# Levantar Master2
sudo docker compose -f docker-compose-pc2.yml up -d --build

# Ver logs del contenedor Master2
sudo docker logs mysql-master2

# Acceder a la consola MySQL de Master2
sudo docker exec -it mysql-master2 mysql -uroot -prootpassword

# Detener servicios de PC2
sudo docker compose -f docker-compose-pc2.yml down

# Detener y eliminar volúmenes (reinicio limpio)
sudo docker compose -f docker-compose-pc2.yml down -v
```

### Desde cualquier máquina con acceso LAN

```bash
# Configurar la replicación (después de levantar ambos nodos)
./setup-replication.sh

# Ver contenedores activos (en cada PC)
sudo docker ps

# Ver respaldos disponibles (en PC1)
ls -lh backups/
```

---

## ❓ Solución de Problemas

### No se puede conectar al otro nodo

1. **Verificar conectividad de red:**
   ```bash
   ping <IP_DEL_OTRO_NODO>
   ```

2. **Verificar que el puerto 3306 está abierto:**
   ```bash
   # Desde PC1, probar conexión a PC2
   nc -zv 192.168.1.101 3306

   # O con telnet
   telnet 192.168.1.101 3306
   ```

3. **Verificar el firewall:**
   ```bash
   # UFW
   sudo ufw status

   # firewalld
   sudo firewall-cmd --list-all

   # iptables
   sudo iptables -L -n | grep 3306
   ```

4. **Verificar que MySQL acepta conexiones externas:**
   ```bash
   sudo docker exec mysql-master1 mysql -uroot -prootpassword -e "SHOW VARIABLES LIKE 'bind_address';"
   # Debe mostrar: 0.0.0.0
   ```

### `Replica_SQL_Running: No`

Revisar el error específico:

```bash
mysql -h <IP_DEL_NODO> -P 3306 -uroot -prootpassword -e "SHOW REPLICA STATUS\G" | grep Error
```

**Solución general:** Reiniciar desde cero con volúmenes limpios:

```bash
# En PC1
sudo docker compose -f docker-compose-pc1.yml down -v
sudo docker compose -f docker-compose-pc1.yml up -d --build

# En PC2
sudo docker compose -f docker-compose-pc2.yml down -v
sudo docker compose -f docker-compose-pc2.yml up -d --build

# Luego reconfigurar la replicación
./setup-replication.sh
```

### Las tablas no aparecen en Master2

Verificar que `setup-replication.sh` se ejecutó después de que los contenedores estuvieran completamente inicializados. El script espera 15 segundos, pero en sistemas lentos puede requerir más tiempo.

### Error de permisos con Docker

Si Docker requiere `sudo`, asegúrate de ejecutar todos los comandos con `sudo` o agrega tu usuario al grupo `docker`:

```bash
sudo usermod -aG docker $USER
# Cerrar sesión y volver a iniciar
```

### Los respaldos no se generan

Verificar que el contenedor `backup-server` esté corriendo en PC1 y revisar los logs:

```bash
sudo docker logs backup-server
cat logs/cron.log
cat logs/backup.log
```

### El backup-server no puede conectarse a Master2

Si el backup-server no alcanza la IP de Master2, verifica:

1. Que `MASTER2_IP` esté correctamente definida en `.env`
2. Que el firewall de PC2 permita conexiones desde PC1
3. Que el contenedor `backup-server` pueda resolver la IP (verificar con `docker exec backup-server ping <MASTER2_IP>`)
