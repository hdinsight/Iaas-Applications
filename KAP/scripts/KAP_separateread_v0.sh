#! /bin/bash

# Providing variables for kylin to restart
export KAP_INSTALL_BASE_FOLDER=/usr/local/kap
export KAP_FOLDER_NAME='kap-2.3.5-GA-hbase1'
export KYLIN_HOME=$KAP_INSTALL_BASE_FOLDER/$KAP_FOLDER_NAME

export ZOOKEEPERADDRESS=`awk '/hbase.zookeeper.quorum/{getline; print}' /etc/hbase/*/0/hbase-site.xml | grep -oP '<value>\K.*(?=</value>)'`
export KYLINPROPERTIESFILE=`ls /usr/local/kap/kap-*-GA-hbase1.x/conf/kylin.properties`

# Setting kylin.server.mode=query
sed -i 's/kylin.server.mode=.*/kylin.server.mode=query/' $KYLINPROPERTIESFILE
# Setting kylin.job.scheduler.default=1
sed -i 's/kylin.job.scheduler.default=.*/kylin.job.scheduler.default=1/' $KYLINPROPERTIESFILE
# Setting kap.job.helix.zookeeper-address
sed -i "s/kap.job.helix.zookeeper-address=.*/kap.job.helix.zookeeper-address=$ZOOKEEPERADDRESS/" $KYLINPROPERTIESFILE


#  Copying hbase-site.xml to hdfs
hadoop fs -put /etc/hbase/*/0/hbase-site.xml /kylin/hbase-site.xml

# Restart of KAP
su kylin -c "export SPARK_HOME=$KYLIN_HOME/spark && $KYLIN_HOME/bin/kylin.sh stop && $KYLIN_HOME/bin/kylin.sh start"
