# 🔄 Replicación Master-Master MySQL con Docker

Sistema de bases de datos MySQL con arquitectura **Master-Master** completamente dockerizado. Ambos nodos funcionan simultáneamente como origen y réplica, permitiendo lecturas y escrituras en cualquiera de los dos. Incluye un servidor de respaldos automáticos.

---

## 📋 Tabla de Contenidos

- [Arquitectura](#-arquitectura)
- [Estructura del Proyecto](#-estructura-del-proyecto)
- [Requisitos Previos](#-requisitos-previos)
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
┌─────────────────────────────────────────────────────────┐
│                    Red Docker: db_net                    │
│                                                         │
│  ┌──────────────┐    replicación    ┌──────────────┐   │
│  │              │ ──────────────▶   │              │   │
│  │ mysql-master1│                   │ mysql-master2│   │
│  │  (server-id=1)│ ◀──────────────  │  (server-id=2)│   │
│  │  Puerto: 3305│    replicación    │  Puerto: 3307│   │
│  └──────┬───────┘                   └──────┬───────┘   │
│         │                                  │           │
│         │         ┌──────────────┐         │           │
│         └────────▶│backup-server │◀────────┘           │
│                   │  (cron cada  │                     │
│                   │   5 minutos) │                     │
│                   └──────────────┘                     │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

**¿Cómo funciona?**

- **Master1** y **Master2** son nodos MySQL 8.0 con replicación bidireccional basada en **GTID** (Global Transaction Identifiers).
- Cualquier escritura (INSERT, UPDATE, DELETE) en un nodo se replica automáticamente al otro.
- El **backup-server** ejecuta `mysqldump` cada 5 minutos contra ambos nodos y almacena los respaldos comprimidos.
- Toda la comunicación entre contenedores ocurre en la red interna `db_net`.

---

## 📁 Estructura del Proyecto

```
Proyecto/
├── docker-compose.yml          # Orquestación de los 3 contenedores
├── setup-replication.sh        # Script para configurar la replicación Master-Master
├── .env                        # Variables de entorno para Master1 y backup-server
├── .env.master2                # Variables de entorno para Master2 (solo root password)
├── .env.example                # Plantilla de ejemplo para .env
├── .gitignore                  # Excluye .env, backups/ y logs/
├── Northwind.sql               # Esquema y datos originales de referencia (Northwind)
│
├── mysql-master1/
│   ├── my.cnf                  # Configuración MySQL: server-id=1, GTID, binlog
│   └── init.sql                # Script de inicialización: usuario replicador + esquema Northwind
│
├── mysql-master2/
│   ├── my.cnf                  # Configuración MySQL: server-id=2, GTID, binlog
│   └── init.sql                # Script mínimo: solo crea el usuario replicador
│
├── backup-server/
│   ├── Dockerfile              # Imagen basada en Debian con mysql-client y cron
│   ├── backup.sh               # Script de respaldo (mysqldump de ambos masters)
│   ├── restore.sh              # Script de restauración desde un archivo .sql.gz
│   └── crontab                 # Programación cron (cada 5 minutos)
│
├── backups/                    # Respaldos generados (montado como volumen)
├── logs/                       # Logs del servidor de respaldos
└── docs/
    └── Manual_de_Uso.md        # Manual de uso detallado
```

### Archivos Clave

| Archivo | Descripción |
|---------|-------------|
| `docker-compose.yml` | Define los 3 servicios (master1, master2, backup-server) y la red `db_net` |
| `setup-replication.sh` | Configura la replicación bidireccional GTID después de levantar los contenedores |
| `mysql-master1/my.cnf` | Habilita binary log, GTID y `log_slave_updates` en Master1 |
| `mysql-master2/my.cnf` | Misma configuración que Master1 pero con `server-id=2` |
| `mysql-master1/init.sql` | Crea el usuario `replicator`, las tablas de Northwind e inserta datos iniciales |
| `mysql-master2/init.sql` | Solo crea el usuario `replicator` (los datos llegan vía replicación) |
| `.env` | Credenciales de Master1: root password, nombre de BD, usuario de aplicación |
| `.env.master2` | Solo el root password (la BD y usuario se crean vía replicación desde Master1) |

---

## ✅ Requisitos Previos

- **Docker** (20.10+)
- **Docker Compose** (v2+)
- **Bash** (para ejecutar `setup-replication.sh`)
- Permisos de `sudo` para ejecutar comandos Docker (o usuario en el grupo `docker`)

---

## 🚀 Inicio Rápido

### 1. Clonar el repositorio

```bash
git clone <URL_DEL_REPOSITORIO>
cd Proyecto
```

### 2. Crear el archivo de variables de entorno

```bash
cp .env.example .env
```

Contenido por defecto de `.env`:

```env
MYSQL_ROOT_PASSWORD=rootpassword
MYSQL_DATABASE=demo_db
MYSQL_USER=demouser
MYSQL_PASSWORD=demopassword
```

> **Nota:** El archivo `.env.master2` ya viene incluido y solo contiene `MYSQL_ROOT_PASSWORD`. No es necesario modificarlo.

### 3. Levantar los contenedores

```bash
sudo docker compose up -d --build
```

Esto creará y levantará:
- `mysql-master1` — MySQL en puerto **3305**
- `mysql-master2` — MySQL en puerto **3307**
- `backup-server` — Respaldos automáticos cada 5 minutos

### 4. Configurar la replicación

```bash
./setup-replication.sh
```

El script:
1. Espera a que ambas bases de datos estén listas
2. Configura Master2 como réplica de Master1 (recibe esquema y datos)
3. Espera a que Master2 esté sincronizado
4. Configura Master1 como réplica de Master2 (completando el ciclo)
5. Verifica el estado de la replicación y muestra las tablas en Master2

**Salida esperada:**

```
Replica_IO_Running: Yes
Replica_SQL_Running: Yes
Seconds_Behind_Source: 0
```

### 5. ¡Listo! Verificar la sincronización

```bash
# Insertar en Master1
sudo docker exec mysql-master1 mysql -uroot -prootpassword -e \
  "INSERT INTO demo_db.Categories VALUES(99, 'Test', 'Prueba de sincronización');"

# Verificar en Master2
sudo docker exec mysql-master2 mysql -uroot -prootpassword -e \
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
```

#### ¿Por qué cada parámetro?

- **`gtid_mode=ON`**: Cada transacción tiene un ID único global, facilitando la sincronización y evitando duplicados.
- **`log_slave_updates=ON`**: Sin esto, los cambios recibidos por replicación no se escriben al binlog, lo que rompe la replicación en sentido inverso.
- **`binlog_format=ROW`**: Replica los datos exactos modificados (más seguro que replicar la sentencia SQL).

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

El contenedor `backup-server` ejecuta un **cron job** cada 5 minutos que:

1. Realiza `mysqldump` de la base de datos `demo_db` en **ambos** masters
2. Comprime cada respaldo con `gzip`
3. Almacena los archivos en el directorio `backups/` del host
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
sudo docker exec backup-server /restore.sh <host_destino> <archivo_respaldo>
```

**Ejemplo:**

```bash
sudo docker exec backup-server /restore.sh mysql-master1 /backups/master1_20260609_120000.sql.gz
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
sudo docker exec mysql-master1 mysql -uroot -prootpassword -e "SHOW REPLICA STATUS\G"

# Estado en Master2 (replicando desde Master1)
sudo docker exec mysql-master2 mysql -uroot -prootpassword -e "SHOW REPLICA STATUS\G"
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
sudo docker exec mysql-master1 mysql -uroot -prootpassword -e \
  "INSERT INTO demo_db.Categories VALUES(99, 'Test', 'Desde Master1');"
sudo docker exec mysql-master2 mysql -uroot -prootpassword -e \
  "SELECT * FROM demo_db.Categories WHERE CategoryID = 99;"

# Master2 → Master1
sudo docker exec mysql-master2 mysql -uroot -prootpassword -e \
  "INSERT INTO demo_db.Categories VALUES(100, 'Reverse', 'Desde Master2');"
sudo docker exec mysql-master1 mysql -uroot -prootpassword -e \
  "SELECT * FROM demo_db.Categories WHERE CategoryID = 100;"
```

---

## 🔌 Conexión a las Bases de Datos

### Desde el host

| Nodo | Host | Puerto | Usuario | Contraseña | Base de datos |
|------|------|--------|---------|------------|---------------|
| Master1 | `localhost` | `3305` | `demouser` | `demopassword` | `demo_db` |
| Master2 | `localhost` | `3307` | `demouser` | `demopassword` | `demo_db` |
| Cualquiera (root) | `localhost` | `3305` / `3307` | `root` | `rootpassword` | `demo_db` |

**Ejemplo con cliente MySQL:**

```bash
mysql -h 127.0.0.1 -P 3305 -u demouser -pdemopassword demo_db
```

### Desde otro contenedor en la misma red

Usar los nombres de contenedor como hostname: `mysql-master1` o `mysql-master2`, puerto `3306`.

---

## 🛠 Comandos Útiles

```bash
# Levantar todos los servicios
sudo docker compose up -d --build

# Configurar la replicación (después de levantar)
./setup-replication.sh

# Ver logs de un contenedor
sudo docker logs mysql-master1
sudo docker logs mysql-master2

# Acceder a la consola MySQL de un nodo
sudo docker exec -it mysql-master1 mysql -uroot -prootpassword

# Ver contenedores activos
sudo docker ps

# Detener todos los servicios
sudo docker compose down

# Detener y eliminar volúmenes (reinicio limpio)
sudo docker compose down -v

# Forzar respaldo manual
sudo docker exec backup-server /backup.sh

# Ver respaldos disponibles
ls -lh backups/
```

---

## ❓ Solución de Problemas

### `Replica_SQL_Running: No`

Revisar el error específico:

```bash
sudo docker exec mysql-master1 mysql -uroot -prootpassword -e "SHOW REPLICA STATUS\G" | grep Error
```

**Solución general:** Reiniciar desde cero con volúmenes limpios:

```bash
sudo docker compose down -v
sudo docker compose up -d --build
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

Verificar que el contenedor `backup-server` esté corriendo y revisar los logs:

```bash
sudo docker logs backup-server
cat logs/cron.log
cat logs/backup.log
```
