-- Master 2: Create replication and admin users only.
-- Disable binlog so these statements don't generate GTIDs
-- (avoids conflicts when master1 replicates from master2).
SET sql_log_bin = 0;
CREATE USER IF NOT EXISTS 'replicator'@'%' IDENTIFIED BY 'replpassword';
GRANT REPLICATION SLAVE ON *.* TO 'replicator'@'%';
-- Usuario administrador para conexión remota desde la LAN.
-- root permanece restringido a localhost; este usuario permite
-- a los scripts de replicación conectarse vía IPs de la red.
CREATE USER IF NOT EXISTS 'admin_lan'@'%' IDENTIFIED BY 'admin_secure_pass';
GRANT ALL PRIVILEGES ON *.* TO 'admin_lan'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SET sql_log_bin = 1;
