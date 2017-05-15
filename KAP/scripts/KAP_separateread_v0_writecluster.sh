#! /bin/bash
export CONTAINERNAME=$1
export STORAGEACCTNAME=$2
export ACCOUNTREGION=$3
export KYLINPROPERTIESFILE=`ls /usr/local/kap/kap-*-GA-hbase1.x/conf/kylin.properties`

if [ "$ACCOUNTREGION" = "china" ]; then
  export $BLOBSTOREADDRESS='blob.core.chinacloudapi.cn'
else
  export $BLOBSTOREADDRESS='blob.core.windows.net'
fi

export STORAGESTRING=$STORAGEACCTNAME"."$BLOBSTOREADDRESS

# Copy hbase config file
"/usr/bin/hadoop fs -get wasb://"$CONTAINERNAME"@"$STORAGESTRING"/kylin/hbase-site.xml" $KYLINPROPERTIESFILE
export ZOOKEEPERADDRESS=`awk '/hbase.zookeeper.quorum/{getline; print}' /etc/hbase/*/0/hbase-site.xml | grep -oP '<value>\K.*(?=</value>)'`

export KYLIN_JOB_CONF=`ls /usr/local/kap/kap-*-GA-hbase1.x/conf/kylin_job_conf.xml`
sed -i '\$i <property>
    <name>hdp.version</name>
    <value>2.5.4.0-121</value>
</property>
' $KYLIN_JOB_CONF

export KYLIN_JOB_CONF_INMEM=`ls /usr/local/kap/kap-*-GA-hbase1.x/conf/kylin_job_conf_inmem.xml`
sed -i '\$i <property>
    <name>hdp.version</name>
    <value>2.5.4.0-121</value>
</property>
' $KYLIN_JOB_CONF_INMEM

# Setting kylin.server.mode=query
sed -i 's/kylin.server.mode=.*/kylin.server.mode=query/' $KYLINPROPERTIESFILE
# Setting kylin.job.scheduler.default=1
sed -i 's/kylin.job.scheduler.default=.*/kylin.job.scheduler.default=1/' $KYLINPROPERTIESFILE
# Setting kap.job.helix.zookeeper-address
sed -i "s/kap.job.helix.zookeeper-address=.*/kap.job.helix.zookeeper-address=$ZOOKEEPERADDRESS/" $KYLINPROPERTIESFILE
# Setting of cluster-fs
sed -i "s/.*kylin.storage.hbase.cluster-fs=.*/kylin.storage.hbase.cluster-fs=wasb:\/\/$CONTAINERNAME@$STORAGESTRING/" $KYLINPROPERTIESFILE
