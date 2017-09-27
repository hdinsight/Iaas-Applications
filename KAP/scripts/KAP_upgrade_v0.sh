#! /bin/bash

# In upgrade process, first we run uninstall, then we reinstall it.

######## Parameters ########
echo "Starting at "`date +'%Y%m%d%H%M'`

env="$1"
kapPackageUrl="$2"
kyAnalyzerPackageUrl="$3"
zeppelinPackageUrl="$4"
metastore="$5"


KAP_TARFILE=`basename "$kapPackageUrl"`
KYANALYZER_TARFILE=`basename "$kyAnalyzerPackageUrl"`
ZEPPELIN_TARFILE=`basename "$zeppelinPackageUrl"`
KAP_FOLDER_NAME=kap
KAP_INSTALL_BASE_FOLDER=/usr/local
KAP_TMPFOLDER=/tmp/kap
KAP_SECURITY_TEMPLETE_URI=https://raw.githubusercontent.com/Kyligence/Iaas-Applications/master/KAP/files/kylinSecurity.xml
KYANALYZER_FOLDER_NAME=kyanalyzer-server
ZEPPELIN_FOLDER_NAME=zeppelin
ZEPPELIN_INSTALL_BASE_FOLDER=/usr/local
ZEPPELIN_TMPFOLDER=/tmp/zeppelin

BACKUP_DIR=/kycloud/backup

newInstall=false

#import helper module.
wget -O /tmp/HDInsightUtilities-v01.sh -q https://hdiconfigactions.blob.core.windows.net/linuxconfigactionmodulev01/HDInsightUtilities-v01.sh && source /tmp/HDInsightUtilities-v01.sh && rm -f /tmp/HDInsightUtilities-v01.sh

######## Backup KAP & Kyanalyzer & Zeppelin ########
kap_dir="/usr/local/kap"
kyanalyzer_dir="/usr/local/kyanalyzer"
zeppelin_dir="/usr/local/zeppelin"

base_backup_dir="/kycloud/backup"
kap_backup_dir=$base_backup_dir/kap
kyanalyzer_backup_dir=$base_backup_dir/kyanalyzer
zeppelin_backup_dir=$base_backup_dir/zeppelin


removeKAP() {
    if [ -d "$kap_dir" ]; then
      rm -rf $kap_dir
    fi
}

removeKyAnalyzer() {
    if [ -d "$kyanalyzer_dir" ]; then
      rm -rf $kyanalyzer_dir
    fi
}

removeZeppelin() {
    if [ -d "$zeppelin_dir" ]; then
      rm -rf $zeppelin_dir
    fi
}

backupKAP() {
    hdfs dfs -mkdir -p $kap_backup_dir
    hdfs dfs -put -f $kap_dir/conf $kap_backup_dir
}

backupKyAnalyzer() {
	hdfs dfs -rm -r -f -skipTrash $kyanalyzer_backup_dir
    hdfs dfs -mkdir -p $kyanalyzer_backup_dir
    hdfs dfs -put -f $kyanalyzer_dir/data $kyanalyzer_backup_dir/data
    hdfs dfs -put -f $kyanalyzer_dir/repository $kyanalyzer_backup_dir/repository
    hdfs dfs -put -f $kyanalyzer_dir/conf $kyanalyzer_backup_dir/conf
}

backupZeppelin() {
    hdfs dfs -mkdir -p $zeppelin_backup_dir
    hdfs dfs -put $zeppelin_dir $zeppelin_backup_dir
}

downloadAndUnzipKAP() {
    echo "Removing KAP tmp folder"
    rm -rf $KAP_TMPFOLDER
    mkdir $KAP_TMPFOLDER

    echo "Downloading KAP tar file"
    wget $kapPackageUrl -P $KAP_TMPFOLDER

    echo "Unzipping KAP"
    mkdir -p $KAP_INSTALL_BASE_FOLDER
    tar -zxvf $KAP_TMPFOLDER/$KAP_TARFILE -C $KAP_INSTALL_BASE_FOLDER
    mv $KAP_INSTALL_BASE_FOLDER/${KAP_TARFILE%.tar.gz*} $KAP_INSTALL_BASE_FOLDER/$KAP_FOLDER_NAME
    
    # Remove old before unzip
    rm -rf kylin
    unzip kylin.war -d kylin
    
    echo "Updating KAP metastore to $metastore"
    cd $KAP_INSTALL_BASE_FOLDER/$KAP_FOLDER_NAME/conf
    sed -i "s/kylin_default_instance/$metastore/g" kylin.properties

    echo "Updating working dir"
    sed -i "s/kylin.env.hdfs-working-dir=\/kylin/kylin.env.hdfs-working-dir=wasb:\/\/\/kylin/g" kylin.properties

    rm -rf $KAP_TMPFOLDER
}

startKapService() {
    # su kylin -c "export SPARK_HOME=$KYLIN_HOME/spark && $KYLIN_HOME/bin/kylin.sh start"
    # sleep 15
    if [ "$env" = "HDINSIGHT" ]; then
        wget https://raw.githubusercontent.com/Kyligence/Iaas-Applications/master/KAP/files/kap.service -O /etc/systemd/system/kap.service
        systemctl daemon-reload
        systemctl enable kap
        systemctl start kap
    else
        service kap start;
    fi
    sleep 15
}

stopKapService() {
    if [ "$env" = "HDINSIGHT" ]; then
        systemctl stop kap
    else
        service kap stop;
    fi
    sleep 15
}

startKAP() {
    echo "Adding kylin user"
    useradd -r kylin
    chown -R kylin:kylin $KAP_INSTALL_BASE_FOLDER/$KAP_FOLDER_NAME
    export KYLIN_HOME=$KAP_INSTALL_BASE_FOLDER/$KAP_FOLDER_NAME

    echo "Create default working dir /kylin"
    su kylin -c "hdfs dfs -mkdir -p /kylin"

    ## Add index page to auto redirect to KAP
    mkdir -p $KYLIN_HOME/tomcat/webapps/ROOT
    cat > $KYLIN_HOME/tomcat/webapps/ROOT/index.html <<EOL
<html>
  <head>
    <meta http-equiv="refresh" content="1;url=kylin">
  </head>
</html>
EOL

    if [ "$newInstall" = true ] ; then
        echo "bypass" > $KYLIN_HOME/bin/check-env-bypass
        echo "Creating sample cube"
        su kylin -c "export SPARK_HOME=$KYLIN_HOME/spark && $KYLIN_HOME/bin/sample.sh"
    fi

    # Update HBase Coprocessor
    echo "Updating HBase Coprocessor with kylin user"
    su kylin -c "export SPARK_HOME=$KYLIN_HOME/spark && $KYLIN_HOME/bin/kylin.sh org.apache.kylin.storage.hbase.util.DeployCoprocessorCLI  default  all || true"

    echo "Starting KAP with kylin user"
    startKapService
}

downloadAndUnzipKyAnalyzer() {
    rm -rf $KAP_TMPFOLDER
    mkdir $KAP_TMPFOLDER

    echo "Downloading KyAnalyzer tar file"
    wget $kyAnalyzerPackageUrl -P $KAP_TMPFOLDER

    echo "Unzipping KyAnalyzer"
    mkdir -p $KAP_INSTALL_BASE_FOLDER
    tar -zxvf $KAP_TMPFOLDER/$KYANALYZER_TARFILE -C $KAP_INSTALL_BASE_FOLDER
    mv $KAP_INSTALL_BASE_FOLDER/kyanalyzer-server* $KAP_INSTALL_BASE_FOLDER/$KYANALYZER_FOLDER_NAME

    rm -rf $KAP_TMPFOLDER
}

startKyAnalyzer() {

    echo "Starting KyAnalyzer with kylin user"
    export KYANALYZER_HOME=$KAP_INSTALL_BASE_FOLDER/$KYANALYZER_FOLDER_NAME

    if [ "$env" = "HDINSIGHT" ]; then
        wget https://raw.githubusercontent.com/Kyligence/Iaas-Applications/master/KAP/files/kyanalyzer.service -O /etc/systemd/system/kyanalyzer.service
        systemctl daemon-reload
        systemctl enable kyanalyzer
        systemctl start kyanalyzer
    else
        service kyanalyzer start;
    fi
    sleep 10

}

stopKyAnalyzerService() {
    if [ "$env" = "HDINSIGHT" ]; then
        systemctl stop kyanalyzer
    else
        service kyanalyzer stop;
    fi
    sleep 10
}

downloadAndUnzipZeppelin() {
    echo "Removing Zeppelin tmp folder"
    rm -rf $ZEPPELIN_TMPFOLDER
    mkdir $ZEPPELIN_TMPFOLDER

    echo "Downloading ZEPPELIN tar file"
    wget $zeppelinPackageUrl -P $ZEPPELIN_TMPFOLDER

    echo "Unzipping ZEPPELIN"
    mkdir -p $ZEPPELIN_INSTALL_BASE_FOLDER
    tar -xzvf $ZEPPELIN_TMPFOLDER/$ZEPPELIN_TARFILE -C $ZEPPELIN_INSTALL_BASE_FOLDER

    rm -rf $ZEPPELIN_TMPFOLDER
}

startZeppelin() {
    echo "Adding zeppelin user"
    useradd -r zeppelin
    chown -R zeppelin:zeppelin $ZEPPELIN_INSTALL_BASE_FOLDER

    export ZEPPELIN_HOME=$ZEPPELIN_INSTALL_BASE_FOLDER/$ZEPPELIN_FOLDER_NAME
    cp $ZEPPELIN_HOME/conf/zeppelin-site.xml.template $ZEPPELIN_HOME/conf/zeppelin-site.xml
    sed -i 's/8080/9090/g' $ZEPPELIN_HOME/conf/zeppelin-site.xml

    echo "Starting zeppelin with zeppelin user"
    su - zeppelin -c "$ZEPPELIN_HOME/bin/zeppelin-daemon.sh start"

    sleep 10
}

installKAP() {
    downloadAndUnzipKAP
    restoreKAP
    startKAP
}

installKyAnalyzer() {
    downloadAndUnzipKyAnalyzer
    restoreKyAnalyzer
    startKyAnalyzer
}

installZeppelin() {
    downloadAndUnzipZeppelin
    restoreZeppelin
    startZeppelin
}

restoreKAP() {
    hdfs dfs -test -e $BACKUP_DIR/kap
    if [ $? -eq 0 ]; then
        newInstall=false
        echo "restore kap..."
        cd $KAP_INSTALL_BASE_FOLDER/$KAP_FOLDER_NAME
        rm -rf $KAP_INSTALL_BASE_FOLDER/$KAP_FOLDER_NAME/conf
        hdfs dfs -get $BACKUP_DIR/kap/conf $KAP_INSTALL_BASE_FOLDER/$KAP_FOLDER_NAME
    fi
}

restoreKyAnalyzer() {
    hdfs dfs -test -e $BACKUP_DIR/kyanalyzer
    if [ $? -eq 0 ]; then
        echo "restore kyanalyzer..."
        kyanalyzer_dir=$KAP_INSTALL_BASE_FOLDER/$KYANALYZER_FOLDER_NAME
        rm -rf $kyanalyzer_dir/data $kyanalyzer_dir/repository $kyanalyzer_dir/conf
        hdfs dfs -get $BACKUP_DIR/kyanalyzer/data $kyanalyzer_dir
        hdfs dfs -get $BACKUP_DIR/kyanalyzer/repository $kyanalyzer_dir
        hdfs dfs -get $BACKUP_DIR/kyanalyzer/conf $kyanalyzer_dir
    fi
}

restoreZeppelin() {
    echo "Not implement yet."
}

main() {
    if [ "$kapPackageUrl" != "" ]; then
        stopKapService
        backupKAP
        removeKAP
        installKAP
    fi
    if [ "$kyAnalyzerPackageUrl" != "" ]; then
        stopKyAnalyzerService
        backupKyAnalyzer
        removeKyAnalyzer
        installKyAnalyzer
    fi
    if [ "$zeppelinPackageUrl" != "" ]; then
        # Kill zeppelin
        export pid=`ps -ef| grep zeppelin | awk 'NR==1{print $2}' | cut -d' ' -f1`;kill $pid || true
        removeZeppelin
        installZeppelin;
    fi
}

##############################
if [ "$(id -u)" != "0" ]; then
    echo "[ERROR] The script has to be run as root."
    exit 1
fi

export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64

# if [ -e $KAP_INSTALL_BASE_FOLDER/$KAP_FOLDER_NAME ]; then
#     echo "KAP is already the latest version. Exiting ..."
#     exit 0
# fi

# if [ -e $ZEPPELIN_INSTALL_BASE_FOLDER/$ZEPPELIN_FOLDER_NAME ]; then
#     echo "Zeppelin is already the latest version. Exiting ..."
#     exit 0
# fi

###############################
main
echo "End at "`date +'%Y%m%d%H%M'`
