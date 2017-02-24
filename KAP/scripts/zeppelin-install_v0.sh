#! /bin/bash

ZEPPELIN_TARFILE=zeppelin-0.8.0-kylin.tar.gz
ZEPPELIN_FOLDER_NAME="${ZEPPELIN_TARFILE%.tar.gz*}"
ZEPPELIN_DOWNLOAD_URI=https://kyligencekeys.blob.core.windows.net/kap-binaries/$ZEPPELIN_TARFILE
ZEPPELIN_INSTALL_BASE_FOLDER=/usr/local/zeppelin
ZEPPELIN_TMPFOLDER=/tmp/zeppelin

#import helper module.
wget -O /tmp/HDInsightUtilities-v01.sh -q https://hdiconfigactions.blob.core.windows.net/linuxconfigactionmodulev01/HDInsightUtilities-v01.sh && source /tmp/HDInsightUtilities-v01.sh && rm -f /tmp/HDInsightUtilities-v01.sh


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

##############################
if [ "$(id -u)" != "0" ]; then
    echo "[ERROR] The script has to be run as root."
    exit 1
fi

export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64

if [ -e $ZEPPELIN_INSTALL_BASE_FOLDER/$ZEPPELIN_FOLDER_NAME ]; then
    echo "Zeppelin is already installed. Exiting ..."
    exit 0
fi

echo "Download and unzip zeppelin"
downloadAndUnzipZeppelin
echo "Start Zeppelin"
startZeppelin
echo "Start Zeppelin Done!"

