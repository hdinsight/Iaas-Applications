#! /bin/bash
export CONTAINERNAME=$1
export STORAGEACCTNAME=$2
export ACCOUNTREGION=$3
export STORAGEACCTNAMEWR=$4

# echo "$@" >> /root/allvar.txt

# Providing variables for kylin to restart
export KAP_INSTALL_BASE_FOLDER=/usr/local
cd $KAP_INSTALL_BASE_FOLDER
export KAP_FOLDER_NAME=kap
cd -
#export KAP_FOLDER_NAME='kap-2.3.5-GA-hbase1'
export KYLIN_HOME="$KAP_INSTALL_BASE_FOLDER/$KAP_FOLDER_NAME"

# Setting for local file path
export KYLINPROPERTIESFILE="`ls /usr/local/kap/conf/kylin.properties`"
export HBASEFILE="`ls /etc/hbase/*/0/hbase-site.xml`"

BLOBSTOREADDRESS='blob.core.chinacloudapi.cn'
if [ "$ACCOUNTREGION" == "china" ]; then
  export BLOBSTOREADDRESS='blob.core.chinacloudapi.cn'
else
  export BLOBSTOREADDRESS='blob.core.windows.net'
fi

export STORAGESTRING=$STORAGEACCTNAME'.'$BLOBSTOREADDRESS
export HDFSSTORAGESTRING=$STORAGEACCTNAMEWR'.'$BLOBSTOREADDRESS

# Copy hbase config file
mv $HBASEFILE $HBASEFILE.origin
/usr/bin/hadoop fs -get "wasb://"$CONTAINERNAME"@"$STORAGESTRING"/kylin/hbase-site.xml" $HBASEFILE

# echo "/usr/bin/hadoop fs -get wasb://"$CONTAINERNAME"@"$STORAGESTRING"/kylin/hbase-site.xml" $HBASEFILE >> /root/allvar.txt

export ZOOKEEPERADDRESS=`awk '/hbase.zookeeper.quorum/{getline; print}' $HBASEFILE | grep -oP '<value>\K.*(?=</value>)'`
export HADOOPVERSION="`hadoop fs -ls /hdp/apps | grep -v Found| awk '{print $NF}'|rev | cut -d '/' -f1 | rev`"
export KYLIN_JOB_CON_SETTINGS='    <property>
        <name>hdp.version</name>
        <value>'$HADOOPVERSION'</value>
    </property>
</configuration>
'

export KYLIN_JOB_CONF=/usr/local/kap/conf/kylin_job_conf.xml
export KYLIN_JOB_CONF_INMEM=/usr/local/kap/conf/kylin_job_conf_inmem.xml

sed -i '$ d' $KYLIN_JOB_CONF
sed -i '$ d' $KYLIN_JOB_CONF_INMEM

echo $KYLIN_JOB_CON_SETTINGS >> $KYLIN_JOB_CONF
echo $KYLIN_JOB_CON_SETTINGS >> $KYLIN_JOB_CONF_INMEM

# Setting kylin.server.mode=query
#sed -i 's/kylin.server.mode=.*/kylin.server.mode=all/' $KYLINPROPERTIESFILE
sed -i '/kylin.server.mode/a\kylin.server.mode=all' $KYLINPROPERTIESFILE
# Setting kylin.job.scheduler.default=1
#sed -i 's/kylin.job.scheduler.default=.*/kylin.job.scheduler.default=1/' $KYLINPROPERTIESFILE
sed -i '/kylin.job.scheduler.default/a\kylin.job.scheduler.default=1' $KYLINPROPERTIESFILE
# Setting kap.job.helix.zookeeper-address
sed -i "s/kap.job.helix.zookeeper-address=.*/kap.job.helix.zookeeper-address=$ZOOKEEPERADDRESS/" $KYLINPROPERTIESFILE
# Setting of cluster-fs
sed -i "s/.*kylin.storage.hbase.cluster-fs=.*/kylin.storage.hbase.cluster-fs=wasb:\/\/$CONTAINERNAME@$STORAGESTRING/" $KYLINPROPERTIESFILE

# Setting of hdfs working-dir
sed -i "/kylin.env.hdfs-working-dir/a\kylin.env.hdfs-working-dir=wasb://$CONTAINERNAME@$HDFSSTORAGESTRING/kylin" $KYLINPROPERTIESFILE
# echo "kylin.storage.hbase.cluster-fs=wasb:\/\/$CONTAINERNAME@$STORAGESTRING" >> /root/allvar.txt

# Restart of KAP
# su kylin -c "export KYLIN_HOME=\"`ls -d /usr/local/kap/kap-*-GA-hbase*`\";export SPARK_HOME=$KYLIN_HOME/spark && $KYLIN_HOME/bin/kylin.sh stop && $KYLIN_HOME/bin/kylin.sh start"
# su kylin -c "export SPARK_HOME=$KYLIN_HOME/spark && $KYLIN_HOME/bin/kylin.sh start"
# sleep 15
wget https://raw.githubusercontent.com/Kyligence/Iaas-Applications/master/KAP/files/kap.service -O /etc/systemd/system/kap.service
systemctl daemon-reload
systemctl enable kap
systemctl restart kap
