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

echo "Databases are up. Configuring replication..."

# Configure master 1 to replicate from master 2
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

# Configure master 2 to replicate from master 1
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

echo "Replication setup complete!"
echo "You can check status with:"
echo "sudo docker exec mysql-master1 mysql -uroot -prootpassword -e 'SHOW REPLICA STATUS\G'"
echo "sudo docker exec mysql-master2 mysql -uroot -prootpassword -e 'SHOW REPLICA STATUS\G'"
