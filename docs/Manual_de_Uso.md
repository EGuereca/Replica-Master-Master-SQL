# Manual de Uso - Arquitectura de Backups en MySQL con Docker

Este proyecto implementa una arquitectura basada en contenedores de Docker que incluye dos bases de datos MySQL independientes y un servidor centralizado encargado de realizar respaldos (backups) automáticos y periódicos.

## Estructura del Proyecto

- `docker-compose.yml`: Define los servicios, redes y volúmenes de la arquitectura.
- `.env`: Archivo de configuración que contiene las credenciales de la base de datos de manera segura.
- `mysql-master1/` y `mysql-master2/`: Contienen las configuraciones (`my.cnf`) y scripts de inicialización (`init.sql`) de las bases de datos.
- `backup-server/`: Contiene el `Dockerfile`, el programador de tareas (`crontab`) y los scripts en Bash para respaldar y restaurar.
- `backups/`: Directorio donde se almacenan físicamente los archivos `.sql.gz` generados.
- `logs/`: Directorio donde se guardan los registros detallados de las operaciones de respaldo.
- `docs/`: Directorio destinado a la documentación del proyecto, como este manual.

## Requisitos Previos

- Tener instalado **Docker** y **Docker Compose**.

## Configuración Inicial

1. **Credenciales:** Asegúrate de que el archivo `.env` en la raíz del proyecto tenga las credenciales correctas.
2. **Frecuencia de Respaldos:** Por defecto, el `cronjob` está configurado para ejecutarse **cada minuto** para que puedas probar la funcionalidad rápidamente (`* * * * *`). Si deseas cambiar esto para un entorno real (por ejemplo, diariamente a las 2 AM), debes modificar el archivo `backup-server/crontab` a:
   ```text
   0 2 * * * /backup.sh >> /logs/cron.log 2>&1
   ```
   *(Asegúrate de dejar una línea en blanco al final de este archivo).*

## Cómo Levantar el Entorno

Para iniciar todos los servicios (bases de datos y servidor de backups), abre una terminal en la raíz del proyecto y ejecuta:

```bash
docker compose up -d --build
```
*(Nota: Si usas una versión anterior, el comando es `docker-compose up -d --build`)*

Este comando construirá la imagen del servidor de respaldos y pondrá a correr los tres contenedores en segundo plano.

## Funcionamiento del Respaldo Automático

Una vez que los contenedores están en ejecución, el contenedor `backup-server` iniciará el servicio de `cron`.

1. En la frecuencia definida, el sistema ejecutará el script `backup.sh`.
2. El script se conectará tanto a `mysql-master1` como a `mysql-master2` utilizando las credenciales cargadas en memoria.
3. Extraerá un volcado completo de la base de datos (`mysqldump`) y lo comprimirá usando `gzip`.
4. Los archivos comprimidos se guardarán en la carpeta local `./backups/`, con nombres que incluyen una marca de tiempo para su fácil identificación (ej. `master1_20231026_120000.sql.gz`).
5. Podrás verificar el estado, los éxitos o errores de los respaldos revisando el archivo local `./logs/backup.log`.

## Restauración de un Respaldo (Restore)

Si ocurre un desastre o necesitas restaurar la base de datos a un estado anterior usando uno de los respaldos generados, sigue estos pasos:

1. Localiza el archivo de respaldo que deseas restaurar en tu carpeta local `backups/` (por ejemplo, `master1_20231026_120000.sql.gz`).
2. Utiliza el contenedor de respaldos para ejecutar el script de restauración indicando hacia cuál servidor enviar los datos (`mysql-master1` o `mysql-master2`), ejecutando un comando similar a este desde tu terminal:

```bash
docker exec -it backup-server /restore.sh mysql-master1 /backups/master1_20231026_120000.sql.gz
```
*(Reemplaza `mysql-master1` por `mysql-master2` si es el caso, y ajusta el nombre del archivo de respaldo por el que deseas utilizar).*

3. El script se encargará de descomprimir el archivo al vuelo (`gunzip -c`) e inyectar los datos de vuelta en la base de datos destino de manera automática.

## Detener el Entorno

Para apagar los contenedores de forma segura y sin perder la configuración:

```bash
docker compose down
```

Tus datos persistirán gracias a los volúmenes configurados, y tus respaldos generados permanecerán intactos en la carpeta `backups/`.
