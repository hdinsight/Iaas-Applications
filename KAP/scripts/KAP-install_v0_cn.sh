#! /bin/bash

KAP_TARFILE=kap-2.2.5-GA-hbase1.x.tar.gz
KAP_FOLDER_NAME="${KAP_TARFILE%.tar.gz*}"
KAP_DOWNLOAD_URI=https://kyhub.blob.core.chinacloudapi.cn/packages/kap/$KAP_TARFILE
KAP_INSTALL_BASE_FOLDER=/usr/local/kap
KAP_TMPFOLDER=/tmp/kap
KAP_SECURITY_TEMPLETE_URI=https://raw.githubusercontent.com/Kyligence/Iaas-Applications/master/KAP/files/kylinSecurity.xml

KYANALYZER_TARFILE=KyAnalyzer-2.1.3.tar.gz
KYANALYZER_FOLDER_NAME=kyanalyzer-server
KYANALYZER_DOWNLOAD_URI=https://kyhub.blob.core.chinacloudapi.cn/packages/kyanalyzer/$KYANALYZER_TARFILE

ZEPPELIN_TARFILE=zeppelin-0.8.0-kylin.tar.gz
ZEPPELIN_FOLDER_NAME="${ZEPPELIN_TARFILE%.tar.gz*}"
ZEPPELIN_DOWNLOAD_URI=https://kyhub.blob.core.chinacloudapi.cn/packages/zeppelin/$ZEPPELIN_TARFILE
ZEPPELIN_INSTALL_BASE_FOLDER=/usr/local/zeppelin
ZEPPELIN_TMPFOLDER=/tmp/zeppelin

adminuser=$1
adminpassword=$2
metastore=$3
apptype=$4

#import helper module.
wget -O /tmp/HDInsightUtilities-v01.sh -q https://hdiconfigactions.blob.core.windows.net/linuxconfigactionmodulev01/HDInsightUtilities-v01.sh && source /tmp/HDInsightUtilities-v01.sh && rm -f /tmp/HDInsightUtilities-v01.sh


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

    echo "Starting KAP with kylin user"
    ## su kylin
    export KYLIN_HOME=$KAP_INSTALL_BASE_FOLDER/$KAP_FOLDER_NAME

    ## Add index page to auto redirect to KAP 
    mkdir -p $KYLIN_HOME/tomcat/webapps/ROOT
    cat > $KYLIN_HOME/tomcat/webapps/ROOT/index.html <<EOL
<html>
  <head>
    <meta http-equiv="refresh" content="1;url=kylin"> 
  </head>
</html>
EOL
   
    # create default working dir /kylin
    su kylin -c "hdfs dfs -mkdir -p /kylin" 
    su kylin -c "$KYLIN_HOME/bin/kylin.sh start"
    sleep 10

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
    startKAP
}

installKyAnalyzer() {
    downloadAndUnzipKyAnalyzer
    startKyAnalyzer
}

installZeppelin() {
    downloadAndUnzipZeppelin
    startZeppelin
}

main() {
    case "$apptype" in
        KAP+KyAnalyzer+Zeppelin)
            installKAP
            installKyAnalyzer
            installZeppelin
            ;;
        KAP+KyAnalyzer)
            installKAP
            installKyAnalyzer
            ;;
        KAP)
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

if [ -e $KAP_INSTALL_BASE_FOLDER/$KAP_FOLDER_NAME ]; then
    echo "KAP is already installed. Exiting ..."
    exit 0
fi

if [ -e $ZEPPELIN_INSTALL_BASE_FOLDER/$ZEPPELIN_FOLDER_NAME ]; then
    echo "Zeppelin is already installed. Exiting ..."
    exit 0
fi

###############################
main

