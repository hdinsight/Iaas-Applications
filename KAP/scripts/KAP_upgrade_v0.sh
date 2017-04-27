#! /bin/bash

# In upgrade process, first we run uninstall, then we reinstall it.
# but before upgrade, we check if the current version is latest

######## Parameters ########
echo "Starting at "`date +'%Y%m%d%H%M'`
apptype=$1
adminuser=$2
adminpassword=$3
metastore=$4

# Default upgrading everything to latest
#KAP_TARFILE=kap-2.3.0-GA-hbase1.x.tar.gz
KAP_TARFILE=kap-2.3.3-GA-hbase1.x.tar.gz
KYANALYZER_TARFILE=KyAnalyzer-2.3.0.tar.gz
ZEPPELIN_TARFILE=zeppelin-0.8.0-kylin.tar.gz
KAP_FOLDER_NAME="${KAP_TARFILE%.tar.gz*}"
KAP_INSTALL_BASE_FOLDER=/usr/local/kap
KAP_TMPFOLDER=/tmp/kap
KAP_SECURITY_TEMPLETE_URI=https://raw.githubusercontent.com/Kyligence/Iaas-Applications/master/KAP/files/kylinSecurity.xml
KYANALYZER_FOLDER_NAME=kyanalyzer-server
ZEPPELIN_FOLDER_NAME="${ZEPPELIN_TARFILE%.tar.gz*}"
ZEPPELIN_INSTALL_BASE_FOLDER=/usr/local/zeppelin
ZEPPELIN_TMPFOLDER=/tmp/zeppelin

BACKUP_DIR=/kycloud/backup

newInstall=false

host=`hostname -f`

if [[ "$host" == *chinacloudapp.cn ]]; then
    # download from cn
    echo "Downloading from Azure CN blob"
    KAP_DOWNLOAD_URI=https://kyhub.blob.core.chinacloudapi.cn/packages/kap/$KAP_TARFILE
    KYANALYZER_DOWNLOAD_URI=https://kyhub.blob.core.chinacloudapi.cn/packages/kyanalyzer/$KYANALYZER_TARFILE
    ZEPPELIN_DOWNLOAD_URI=https://kyhub.blob.core.chinacloudapi.cn/packages/zeppelin/$ZEPPELIN_TARFILE
else
    echo "Download from Azure global blob"
    KAP_DOWNLOAD_URI=https://kyligencekeys.blob.core.windows.net/kap-binaries/$KAP_TARFILE
    KYANALYZER_DOWNLOAD_URI=https://kyligencekeys.blob.core.windows.net/kap-binaries/$KYANALYZER_TARFILE
    ZEPPELIN_DOWNLOAD_URI=https://kyligencekeys.blob.core.windows.net/kap-binaries/$ZEPPELIN_TARFILE
fi

#import helper module.
wget -O /tmp/HDInsightUtilities-v01.sh -q https://hdiconfigactions.blob.core.windows.net/linuxconfigactionmodulev01/HDInsightUtilities-v01.sh && source /tmp/HDInsightUtilities-v01.sh && rm -f /tmp/HDInsightUtilities-v01.sh

######## Backup KAP & Kyanalyzer & Zeppelin ########
kap_dir="/usr/local/kap/kap-*"
kyanalyzer_dir="/usr/local/kap/kyanalyzer-server"
zeppelin_dir="/usr/local/zeppelin"

base_backup_dir="/kycloud/backup"
kap_backup_dir=$base_backup_dir/kap
kyanalyzer_backup_dir=$base_backup_dir/kyanalyzer
zeppelin_backup_dir=$base_backup_dir/zeppelin

removelocal() {
    if [ -d "$KAP_INSTALL_BASE_FOLDER" ]; then
      rm -rf $KAP_INSTALL_BASE_FOLDER
    fi 
    if [ -d "$ZEPPELIN_INSTALL_BASE_FOLDER" ]; then
      rm -rf $ZEPPELIN_INSTALL_BASE_FOLDER
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
    wget $KAP_DOWNLOAD_URI -P $KAP_TMPFOLDER
    
    echo "Unzipping KAP"
    mkdir -p $KAP_INSTALL_BASE_FOLDER
    tar -zxvf $KAP_TMPFOLDER/$KAP_TARFILE -C $KAP_INSTALL_BASE_FOLDER

    echo "Updating KAP admin account"
    cd $KAP_INSTALL_BASE_FOLDER/$KAP_FOLDER_NAME/tomcat/webapps/
    # Remove old before unzip
    rm -rf kylin
    unzip kylin.war -d kylin
    wget $KAP_SECURITY_TEMPLETE_URI -P kylin/WEB-INF/classes/
    sed -i "s/KAP-ADMIN/$adminuser/g" kylin/WEB-INF/classes/kylinSecurity.xml
    sed -i "s/KAP-PASSWD/$adminpassword/g" kylin/WEB-INF/classes/kylinSecurity.xml

    echo "Updating KAP metastore to $metastore"
    cd $KAP_INSTALL_BASE_FOLDER/$KAP_FOLDER_NAME/conf
    sed -i "s/kylin_default_instance/$metastore/g" kylin.properties

    echo "Updating working dir"
    sed -i "s/kylin.env.hdfs-working-dir=\/kylin/kylin.env.hdfs-working-dir=wasb:\/\/\/kylin/g" kylin.properties    

    rm -rf $KAP_TMPFOLDER
}

startKAP() {
    echo "Adding kylin user"
    useradd -r kylin
    chown -R kylin:kylin $KAP_INSTALL_BASE_FOLDER
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
    
    echo "Starting KAP with kylin user"
    su kylin -c "export SPARK_HOME=$KYLIN_HOME/spark && $KYLIN_HOME/bin/kylin.sh start"
    sleep 15

    if [ "$newInstall" = true ] ; then
        echo "Trigger a build for sample cube"
        nohup curl -X PUT --user $adminuser:$adminpassword -H "Content-Type: application/json;charset=utf-8" -d '{ "startTime": 1325376000000, "endTime": 1456790400000, "buildType": "BUILD"}' http://localhost:7070/kylin/api/cubes/kylin_sales_cube/rebuild &
        sleep 10
    fi
}

downloadAndUnzipKyAnalyzer() {
    rm -rf $KAP_TMPFOLDER
    mkdir $KAP_TMPFOLDER
    
    echo "Downloading KyAnalyzer tar file"
    wget $KYANALYZER_DOWNLOAD_URI -P $KAP_TMPFOLDER
    
    echo "Unzipping KyAnalyzer"
    mkdir -p $KAP_INSTALL_BASE_FOLDER
    tar -zxvf $KAP_TMPFOLDER/$KYANALYZER_TARFILE -C $KAP_INSTALL_BASE_FOLDER

    rm -rf $KAP_TMPFOLDER
}

startKyAnalyzer() {

    echo "Starting KyAnalyzer with kylin user"
    export KYANALYZER_HOME=$KAP_INSTALL_BASE_FOLDER/$KYANALYZER_FOLDER_NAME
    $KYANALYZER_HOME/start-analyzer.sh
    sleep 10

}

downloadAndUnzipZeppelin() {
    echo "Removing Zeppelin tmp folder"
    rm -rf $ZEPPELIN_TMPFOLDER
    mkdir $ZEPPELIN_TMPFOLDER
    
    echo "Downloading ZEPPELIN tar file"
    wget $ZEPPELIN_DOWNLOAD_URI -P $ZEPPELIN_TMPFOLDER
    
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
    case "$apptype" in
        KAP+KyAnalyzer+Zeppelin)
            backupKAP
            backupKyAnalyzer
            removelocal
            installKAP
            installKyAnalyzer
            installZeppelin
            ;;
        KAP+KyAnalyzer)
            backupKAP
            backupKyAnalyzer
            removelocal
            installKAP
            installKyAnalyzer
            ;;
        KAP)
            backupKAP
            removelocal
            installKAP
            ;;
        *)
            echo "Not Supported APP Type!"
            exit 1
            ;;
    esac
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
