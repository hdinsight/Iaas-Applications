#! /bin/bash

#catch Parameters
export CONTAINERNAME=$1
export STORAGEACCOUNTRD=$2
export STORAGEACCOUNTWR=$3
export STORAGEREGION=$4
# Providing variables for kylin to restart
export KAP_INSTALL_BASE_FOLDER=/usr/local
cd $KAP_INSTALL_BASE_FOLDER
export KAP_FOLDER_NAME="kap"
cd -
# export KAP_FOLDER_NAME='kap-2.3.5-GA-hbase1'
export KYLIN_HOME="$KAP_INSTALL_BASE_FOLDER/$KAP_FOLDER_NAME"

export ZOOKEEPERADDRESS=`awk '/hbase.zookeeper.quorum/{getline; print}' /etc/hbase/*/0/hbase-site.xml | grep -oP '<value>\K.*(?=</value>)'`
export KYLINPROPERTIESFILE="`ls /usr/local/kap/conf/kylin.properties`"

BLOBSTOREADDRESS='blob.core.chinacloudapi.cn'
if [ "$ACCOUNTREGION" == "china" ]; then
  export BLOBSTOREADDRESS='blob.core.chinacloudapi.cn'
else
  export BLOBSTOREADDRESS='blob.core.windows.net'
fi

export HBASESTORAGESTRING=$STORAGEACCOUNTRD'.'$BLOBSTOREADDRESS
export HDFSSTORAGESTRING=$STORAGEACCOUNTWR'.'$BLOBSTOREADDRESS

# Setting kylin.server.mode=query
#sed -i 's/kylin.server.mode=.*/kylin.server.mode=query/' $KYLINPROPERTIESFILE
sed -i '/kylin.server.mode/a\kylin.server.mode=query' $KYLINPROPERTIESFILE
# Setting kylin.job.scheduler.default=1
#sed -i 's/kylin.job.scheduler.default=.*/kylin.job.scheduler.default=1/' $KYLINPROPERTIESFILE
sed -i '/kylin.job.scheduler.default/a\kylin.job.scheduler.default=1' $KYLINPROPERTIESFILE
# Setting kap.job.helix.zookeeper-address
sed -i "/kap.job.helix.zookeeper-address/a\kap.job.helix.zookeeper-address=$ZOOKEEPERADDRESS" $KYLINPROPERTIESFILE

sed -i "/kylin.env.hdfs-working-dir/a\kylin.env.hdfs-working-dir=wasb://$CONTAINERNAME@$HDFSSTORAGESTRING/kylin" $KYLINPROPERTIESFILE

sed -i "/kylin.storage.hbase.cluster-fs/a\kylin.storage.hbase.cluster-fs=wasb://$CONTAINERNAME@$HBASESTORAGESTRING/kylin" $KYLINPROPERTIESFILE

#  Copying hbase-site.xml to hdfs
hadoop fs -put /etc/hbase/*/0/hbase-site.xml /kylin/hbase-site.xml

# Restart of KAP
# su kylin -c "export KYLIN_HOME=\"`ls -d /usr/local/kap/kap-*-GA-hbase*`\";export SPARK_HOME=$KYLIN_HOME/spark && $KYLIN_HOME/bin/kylin.sh stop && $KYLIN_HOME/bin/kylin.sh start"
# su kylin -c "export SPARK_HOME=$KYLIN_HOME/spark && $KYLIN_HOME/bin/kylin.sh start"
# sleep 15
wget https://raw.githubusercontent.com/Kyligence/Iaas-Applications/master/KAP/files/kap.service -O /etc/systemd/system/kap.service
systemctl daemon-reload
systemctl enable kap
systemctl restart kap
