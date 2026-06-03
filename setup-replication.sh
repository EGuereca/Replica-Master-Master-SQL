#!/bin/bash

# Wait for both databases to be ready
echo "Waiting for mysql-master1..."
until sudo docker exec mysql-master1 mysqladmin ping -h localhost --silent; do
    sleep 2
done

echo "Waiting for mysql-master2..."
until sudo docker exec mysql-master2 mysqladmin ping -h localhost --silent; do
    sleep 2
done

# Wait extra time for init scripts to finish executing
echo "Waiting for init scripts to complete..."
sleep 15

echo "Databases are up. Configuring replication..."

# Step 1: Configure master2 to replicate from master1.
# Master2 does NOT have master1's data (its init.sql only created the repl user).
# With SOURCE_AUTO_POSITION=1, master2 sends its gtid_executed to master1,
# and master1 responds with ALL transactions master2 is missing (the full Northwind schema+data).
# DO NOT set gtid_purged — we WANT master2 to request those transactions.
echo "Configuring master2 to replicate from master1..."
sudo docker exec mysql-master2 mysql -uroot -prootpassword -e "
STOP REPLICA;
CHANGE REPLICATION SOURCE TO
  SOURCE_HOST='mysql-master1',
  SOURCE_PORT=3306,
  SOURCE_USER='replicator',
  SOURCE_PASSWORD='replpassword',
  SOURCE_AUTO_POSITION=1,
  GET_SOURCE_PUBLIC_KEY=1;
START REPLICA;
"

# Step 2: Wait for master2 to fully sync all data from master1
echo "Waiting for master2 to sync data from master1..."
for i in $(seq 1 30); do
  BEHIND=$(sudo docker exec mysql-master2 mysql -uroot -prootpassword -N -e \
    "SHOW REPLICA STATUS\G" 2>/dev/null | grep "Seconds_Behind_Source" | awk '{print $2}')
  SQL_RUNNING=$(sudo docker exec mysql-master2 mysql -uroot -prootpassword -N -e \
    "SHOW REPLICA STATUS\G" 2>/dev/null | grep "Replica_SQL_Running:" | awk '{print $2}')

  if [ "$SQL_RUNNING" = "Yes" ] && [ "$BEHIND" = "0" ]; then
    echo "Master2 is fully synced!"
    break
  elif [ "$SQL_RUNNING" != "Yes" ]; then
    echo "WARNING: Replica SQL thread is not running on master2. Checking error..."
    sudo docker exec mysql-master2 mysql -uroot -prootpassword -e "SHOW REPLICA STATUS\G" 2>/dev/null | grep -E "Last.*Error"
    break
  fi
  echo "  Syncing... (Seconds behind: $BEHIND)"
  sleep 2
done

# Step 3: Configure master1 to replicate from master2 (completing the circle)
echo "Configuring master1 to replicate from master2..."
sudo docker exec mysql-master1 mysql -uroot -prootpassword -e "
STOP REPLICA;
CHANGE REPLICATION SOURCE TO
  SOURCE_HOST='mysql-master2',
  SOURCE_PORT=3306,
  SOURCE_USER='replicator',
  SOURCE_PASSWORD='replpassword',
  SOURCE_AUTO_POSITION=1,
  GET_SOURCE_PUBLIC_KEY=1;
START REPLICA;
"

echo ""
echo "Replication setup complete! Verifying status..."
echo ""

# Wait a moment for replication threads to start
sleep 3

# Check replication status on both
echo "=== Master1 Replica Status ==="
sudo docker exec mysql-master1 mysql -uroot -prootpassword -e "SHOW REPLICA STATUS\G" 2>/dev/null | grep -E "Replica_IO_Running|Replica_SQL_Running|Last_Error|Last_IO_Error|Seconds_Behind"

echo ""
echo "=== Master2 Replica Status ==="
sudo docker exec mysql-master2 mysql -uroot -prootpassword -e "SHOW REPLICA STATUS\G" 2>/dev/null | grep -E "Replica_IO_Running|Replica_SQL_Running|Last_Error|Last_IO_Error|Seconds_Behind"

# Quick verification: check that master2 has the tables
echo ""
echo "=== Verification: Tables on master2 ==="
sudo docker exec mysql-master2 mysql -uroot -prootpassword -e "SHOW TABLES FROM demo_db;" 2>/dev/null

echo ""
echo "If both Replica_IO_Running and Replica_SQL_Running show 'Yes', replication is working!"
echo ""
echo "You can test with:"
echo "sudo docker exec mysql-master1 mysql -uroot -prootpassword -e \"INSERT INTO demo_db.Categories VALUES(99,'Test','Sync test');\""
echo "sudo docker exec mysql-master2 mysql -uroot -prootpassword -e \"SELECT * FROM demo_db.Categories WHERE CategoryID=99;\""
