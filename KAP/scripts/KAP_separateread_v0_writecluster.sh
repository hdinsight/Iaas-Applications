#! /bin/bash
export CONTAINERNAME=$1
export STORAGEACCTNAME=$2
export ACCOUNTREGION=$3

echo "$@" >> /root/allvar.txt

export KYLINPROPERTIESFILE=`ls /usr/local/kap/kap-*-GA-hbase1.x/conf/kylin.properties`

BLOBSTOREADDRESS='blob.core.chinacloudapi.cn'
if [ "$ACCOUNTREGION" == "china" ]; then
  export BLOBSTOREADDRESS='blob.core.chinacloudapi.cn'
else
  export BLOBSTOREADDRESS='blob.core.windows.net'
fi

export STORAGESTRING=$STORAGEACCTNAME'.'$BLOBSTOREADDRESS

# Copy hbase config file
"/usr/bin/hadoop fs -get wasb://"$CONTAINERNAME"@"$STORAGESTRING"/kylin/hbase-site.xml" $KYLINPROPERTIESFILE

echo "/usr/bin/hadoop fs -get wasb://"$CONTAINERNAME"@"$STORAGESTRING"/kylin/hbase-site.xml" $KYLINPROPERTIESFILE >> /root/allvar.txt

export ZOOKEEPERADDRESS=`awk '/hbase.zookeeper.quorum/{getline; print}' /etc/hbase/*/0/hbase-site.xml | grep -oP '<value>\K.*(?=</value>)'`

sed -i '$ d' $KYLIN_JOB_CONF
sed -i '$ d' $KYLIN_JOB_CONF_INMEM

export KYLIN_JOB_CON_SETTINGS='    <property>
        <name>hdp.version</name>
        <value>2.5.4.0-121</value>
    </property>
</configuration>
'

export KYLIN_JOB_CONF=`ls /usr/local/kap/kap-*-GA-hbase1.x/conf/kylin_job_conf.xml`
echo $KYLIN_JOB_CON_SETTINGS >> $KYLIN_JOB_CONF
export KYLIN_JOB_CONF_INMEM=`ls /usr/local/kap/kap-*-GA-hbase1.x/conf/kylin_job_conf_inmem.xml`
echo $KYLIN_JOB_CON_SETTINGS >> $KYLIN_JOB_CONF_INMEM

# Setting kylin.server.mode=query
sed -i 's/kylin.server.mode=.*/kylin.server.mode=all/' $KYLINPROPERTIESFILE
# Setting kylin.job.scheduler.default=1
sed -i 's/kylin.job.scheduler.default=.*/kylin.job.scheduler.default=1/' $KYLINPROPERTIESFILE
# Setting kap.job.helix.zookeeper-address
sed -i "s/kap.job.helix.zookeeper-address=.*/kap.job.helix.zookeeper-address=$ZOOKEEPERADDRESS/" $KYLINPROPERTIESFILE
# Setting of cluster-fs
sed -i "s/.*kylin.storage.hbase.cluster-fs=.*/kylin.storage.hbase.cluster-fs=wasb:\/\/$CONTAINERNAME@$STORAGESTRING/" $KYLINPROPERTIESFILE

echo "kylin.storage.hbase.cluster-fs=wasb:\/\/$CONTAINERNAME@$STORAGESTRING" >> /root/allvar.txt
