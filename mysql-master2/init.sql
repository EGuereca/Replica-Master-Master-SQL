-- Master 2: Only create the replication user.
-- Disable binlog so these statements don't generate GTIDs
-- (avoids conflicts when master1 replicates from master2).
SET sql_log_bin = 0;
CREATE USER IF NOT EXISTS 'replicator'@'%' IDENTIFIED BY 'replpassword';
GRANT REPLICATION SLAVE ON *.* TO 'replicator'@'%';
FLUSH PRIVILEGES;
SET sql_log_bin = 1;
