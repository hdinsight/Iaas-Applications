#! /bin/bash

KAP_TARFILE=kap-2.2.2-GA-hbase1.x.tar.gz
KAP_FOLDER_NAME="${KAP_TARFILE%.tar.gz*}"
KAP_DOWNLOAD_URI=https://kyligencekeys.blob.core.windows.net/kap-binaries/$KAP_TARFILE
KAP_INSTALL_BASE_FOLDER=/usr/local/kap
KAP_TMPFOLDER=/tmp/kap

#import helper module.
wget -O /tmp/HDInsightUtilities-v01.sh -q https://hdiconfigactions.blob.core.windows.net/linuxconfigactionmodulev01/HDInsightUtilities-v01.sh && source /tmp/HDInsightUtilities-v01.sh && rm -f /tmp/HDInsightUtilities-v01.sh


downloadAndUnzipKAP() {
    echo "Removing KAP tmp folder"
    rm -rf $KAP_TMPFOLDER
    mkdir $KAP_TMPFOLDER
    
    echo "Downloading Hue tar file"
    wget $KAP_DOWNLOAD_URI -P $KAP_TMPFOLDER
    
    echo "Unzipping KAP"
    mkdir -p $KAP_INSTALL_BASE_FOLDER
    tar -zxvf $KAP_TMPFOLDER/$KAP_TARFILE -C $KAP_INSTALL_BASE_FOLDER

    rm -rf $KAP_TMPFOLDER
}

startKAP() {
    echo "Adding kylin user"
    useradd -r kylin
    chown -R kylin:kylin $KAP_INSTALL_BASE_FOLDER

    echo "Starting KAP with kylin user"
    su - kylin
    export KYLIN_HOME=$KAP_INSTALL_BASE_FOLDER/$KAP_FOLDER_NAME
    $KYLIN_HOME/bin/kylin.sh start
    sleep 10

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

echo "Download and unzip KAP"
downloadAndUnzipKAP
echo "Start KAP"
startKAP
echo "Start KAP Done!"

