#! /bin/bash
CORESITEPATH=/etc/hadoop/conf/core-site.xml
YARNSITEPATH=/etc/hadoop/conf/yarn-site.xml
AMBARICONFIGS_SH=/var/lib/ambari-server/resources/scripts/configs.sh
PORT=8080

WEBWASB_TARFILE=webwasb-tomcat.tar.gz
WEBWASB_TARFILEURI=https://hdiconfigactions.blob.core.windows.net/linuxhueconfigactionv01/$WEBWASB_TARFILE
WEBWASB_TMPFOLDER=/tmp/webwasb
WEBWASB_INSTALLFOLDER=/usr/share/webwasb-tomcat

HUE_TARFILE=hue-binaries.tgz

OS_VERSION=$(lsb_release -sr)
if [[ $OS_VERSION == 14* ]]; then
    echo "OS verion is $OS_VERSION. Using hue-binaries-14-04."
    HUE_TARFILE=hue-binaries-14-04.tgz
elif [[ $OS_VERSION == 16* ]]; then
    echo "OS verion is $OS_VERSION. Using hue-binaries-16-04."
    HUE_TARFILE=hue-binaries-16-04.tgz
fi

HUE_TARFILEURI=https://hdiconfigactions.blob.core.windows.net/linuxhueconfigactionv01/$HUE_TARFILE
HUE_TMPFOLDER=/tmp/hue
HUE_INSTALLFOLDER=/usr/share/hue
HUE_INIPATH=$HUE_INSTALLFOLDER/desktop/conf/hue.ini
ACTIVEAMBARIHOST=headnodehost

#import helper module.
wget -O /tmp/HDInsightUtilities-v01.sh -q https://hdiconfigactions.blob.core.windows.net/linuxconfigactionmodulev01/HDInsightUtilities-v01.sh && source /tmp/HDInsightUtilities-v01.sh && rm -f /tmp/HDInsightUtilities-v01.sh

usage() {
    echo ""
    echo "Usage: sudo -E bash install-hue-uber-v02.sh";
    echo "This script does NOT require Ambari username and password";
    exit 132;
}

checkHostNameAndSetClusterName() {
    fullHostName=$(hostname -f)
    echo "fullHostName=$fullHostName"
    CLUSTERNAME=$(sed -n -e 's/.*\.\(.*\)-ssh.*/\1/p' <<< $fullHostName)
    if [ -z "$CLUSTERNAME" ]; then
        CLUSTERNAME=$(echo -e "import hdinsight_common.ClusterManifestParser as ClusterManifestParser\nprint ClusterManifestParser.parse_local_manifest().deployment.cluster_name" | python)
        if [ $? -ne 0 ]; then
            echo "[ERROR] Cannot determine cluster name. Exiting!"
            exit 133
        fi
    fi
    echo "Cluster Name=$CLUSTERNAME"
}

validateUsernameAndPassword() {
    coreSiteContent=$(bash $AMBARICONFIGS_SH -u $USERID -p $PASSWD get $ACTIVEAMBARIHOST $CLUSTERNAME core-site)
    if [[ $coreSiteContent == *"[ERROR]"* && $coreSiteContent == *"Bad credentials"* ]]; then
        echo "[ERROR] Username and password are invalid. Exiting!"
        exit 134
    fi
}

updateAmbariConfigs() {
    updateResult=$(bash $AMBARICONFIGS_SH -u $USERID -p $PASSWD set $ACTIVEAMBARIHOST $CLUSTERNAME core-site "hadoop.proxyuser.oozie.groups" "*")
    
    if [[ $updateResult != *"Tag:version"* ]] && [[ $updateResult == *"[ERROR]"* ]]; then
        echo "[ERROR] Failed to update core-site. Exiting!"
        echo $updateResult
        exit 135
    fi
    
    echo "Updated hadoop.proxyuser.hue.groups = *"
    
    updateResult=$(bash $AMBARICONFIGS_SH -u $USERID -p $PASSWD set $ACTIVEAMBARIHOST $CLUSTERNAME oozie-site "oozie.service.ProxyUserService.proxyuser.hue.hosts" "*")
    
    if [[ $updateResult != *"Tag:version"* ]] && [[ $updateResult == *"[ERROR]"* ]]; then
        echo "[ERROR] Failed to update oozie-site. Exiting!"
        echo $updateResult
        exit 135
    fi
    
    echo "Updated oozie.service.ProxyUserService.proxyuser.hue.hosts = *"
    
    updateResult=$(bash $AMBARICONFIGS_SH -u $USERID -p $PASSWD set $ACTIVEAMBARIHOST $CLUSTERNAME oozie-site "oozie.service.ProxyUserService.proxyuser.hue.groups" "*")
    
    if [[ $updateResult != *"Tag:version"* ]] && [[ $updateResult == *"[ERROR]"* ]]; then
        echo "[ERROR] Failed to update oozie-site. Exiting!"
        echo $updateResult
        exit 135
    fi
    
    echo "Updated oozie.service.ProxyUserService.proxyuser.hue.hosts = *"
}

stopServiceViaRest() {
    if [ -z "$1" ]; then
        echo "Need service name to stop service"
        exit 136
    fi
    SERVICENAME=$1
    echo "Stopping $SERVICENAME"
    curl -u $USERID:$PASSWD -i -H 'X-Requested-By: ambari' -X PUT -d '{"RequestInfo": {"context" :"Stop Service for Hue installation"}, "Body": {"ServiceInfo": {"state": "INSTALLED"}}}' http://$ACTIVEAMBARIHOST:$PORT/api/v1/clusters/$CLUSTERNAME/services/$SERVICENAME
}

startServiceViaRest() {
    if [ -z "$1" ]; then
        echo "Need service name to start service"
        exit 136
    fi
    sleep 2
    SERVICENAME=$1
    echo "Starting $SERVICENAME"
    startResult=$(curl -u $USERID:$PASSWD -i -H 'X-Requested-By: ambari' -X PUT -d '{"RequestInfo": {"context" :"Start Service for Hue installation"}, "Body": {"ServiceInfo": {"state": "STARTED"}}}' http://$ACTIVEAMBARIHOST:$PORT/api/v1/clusters/$CLUSTERNAME/services/$SERVICENAME)
    if [[ $startResult == *"500 Server Error"* || $startResult == *"internal system exception occurred"* ]]; then
        sleep 60
        echo "Retry starting $SERVICENAME"
        startResult=$(curl -u $USERID:$PASSWD -i -H 'X-Requested-By: ambari' -X PUT -d '{"RequestInfo": {"context" :"Start Service for Hue installation"}, "Body": {"ServiceInfo": {"state": "STARTED"}}}' http://$ACTIVEAMBARIHOST:$PORT/api/v1/clusters/$CLUSTERNAME/services/$SERVICENAME)
    fi
    echo $startResult
}

downloadAndUnzipWebWasb() {
    echo "Removing WebWasb installation and tmp folder"
    rm -rf $WEBWASB_INSTALLFOLDER/
    rm -rf $WEBWASB_TMPFOLDER/
    mkdir $WEBWASB_TMPFOLDER/
    
    echo "Downloading webwasb tar file"
    wget $WEBWASB_TARFILEURI -P $WEBWASB_TMPFOLDER
    
    echo "Unzipping webwasb-tomcat"
    cd $WEBWASB_TMPFOLDER
    tar -zxvf $WEBWASB_TARFILE -C /usr/share/
    
    rm -rf $WEBWASB_TMPFOLDER/
}

setupWebWasbService() {
    echo "Adding webwasb user"
    useradd -r webwasb

    echo "Making webwasb a service and start it"
    sed -i "s|JAVAHOMEPLACEHOLDER|$JAVA_HOME|g" $WEBWASB_INSTALLFOLDER/upstart/webwasb.conf
    chown -R webwasb:webwasb $WEBWASB_INSTALLFOLDER

    cp -f $WEBWASB_INSTALLFOLDER/upstart/webwasb.conf /etc/init/
	cat >/etc/systemd/system/multi-user.target.wants/webwasb.service <<EOL
[[Unit]
Description=webwasb service

[Service]
Type=simple
User=webwasb
Group=webwasb
Restart=always
RestartSec=5
Environment="JAVA_HOME=$JAVA_HOME"
Environment="CATALINA_HOME=/usr/share/webwasb-tomcat"
ExecStart=/usr/share/webwasb-tomcat/bin/catalina.sh run
ExecStopPost=rm -rf $CATALINA_HOME/temp/*

[Install]
WantedBy=multi-user.target
EOL
	if [[ $OS_VERSION == 16* ]]; then
	    echo "Using systemd configuration"
		systemctl daemon-reload
		systemctl stop webwasb.service    
		systemctl start webwasb.service
	else
	    echo "Using upstart configuration"
        initctl reload-configuration
		stop webwasb
		start webwasb
    fi    
}

downloadAndUnzipHue() {
    echo "Removing Hue tmp folder"
    rm -rf $HUE_TMPFOLDER
    mkdir $HUE_TMPFOLDER
    
    echo "Downloading Hue tar file"
    wget $HUE_TARFILEURI -P $HUE_TMPFOLDER
    
    echo "Unzipping Hue"
    cd $HUE_TMPFOLDER
    tar -zxvf $HUE_TARFILE -C /usr/share/
    
    rm -rf $HUE_TMPFOLDER
}

setupHueService() {
    echo "Installing Hue dependencies"
    export DEBIAN_FRONTEND=noninteractive
    apt-get -q -y install libxslt-dev
    
    echo "Configuring Hue default FS"
    defaultfsnode=$(sed -n '/<name>fs.default/,/<\/value>/p' $CORESITEPATH)
    if [ -z "$defaultfsnode" ]
      then
        echo "[ERROR] Cannot find fs.defaultFS configuration in core-site.xml. Exiting"
        exit 137
    fi

    defaultfs=$(sed -n -e 's/.*<value>\(.*\)<\/value>.*/\1/p' <<< $defaultfsnode)

    sed -i "s|DEFAULTFSPLACEHOLDER|$defaultfs|g" $HUE_INIPATH
    
    PRIMARYHEADNODE=`get_primary_headnode`
	SECONDARYHEADNODE=`get_secondary_headnode`
    
	#Check if values retrieved are empty, if yes, exit with error
	if [[ -z $PRIMARYHEADNODE ]]; then
	echo "Could not determine primary headnode."
	exit 139
	fi
    
	if [[ -z $SECONDARYHEADNODE ]]; then
	echo "Could not determine secondary headnode."
	exit 140
	fi
    
    echo "primary headnode = $PRIMARYHEADNODE"
    echo "secondary headnode = $SECONDARYHEADNODE"
    sed -i "s|http://headnode0:8088|http://$PRIMARYHEADNODE:8088|g" $HUE_INIPATH
    sed -i "s|http://headnode1:8088|http://$SECONDARYHEADNODE:8088|g" $HUE_INIPATH

    sed -i "s|## hive_server_host=localhost|hive_server_host=$PRIMARYHEADNODE|g" $HUE_INIPATH
    sed -i "s|## oozie_url=http://localhost:11000/oozie|oozie_url=http://$PRIMARYHEADNODE:11000/oozie|g" $HUE_INIPATH
    sed -i "s|## proxy_api_url=http://localhost:8088|proxy_api_url=http://$PRIMARYHEADNODE:8088|g" $HUE_INIPATH
    sed -i "s|## history_server_api_url=http://localhost:19888|history_server_api_url=http://$PRIMARYHEADNODE:19888|g" $HUE_INIPATH
    sed -i "s|## jobtracker_host=localhost|jobtracker_host=$PRIMARYHEADNODE|g" $HUE_INIPATH

    echo "Adding hue user"
    useradd -r hue
    chown -R hue:hue /usr/share/hue

    echo "Making Hue a service and start it"
    cp $HUE_INSTALLFOLDER/upstart/hue.conf /etc/init/
    cat >/etc/systemd/system/multi-user.target.wants/hue.service <<EOL
[[Unit]
Description=hue service

[Service]
Type=simple
User=hue
Restart=always
ExecStart=/usr/share/hue/build/env/bin/supervisor

[Install]
WantedBy=multi-user.target
EOL
	if [[ $OS_VERSION == 16* ]]; then
	    echo "Using systemd configuration"
		systemctl daemon-reload
		systemctl stop hue.service    
		systemctl start hue.service
	else
	    echo "Using upstart configuration"
        initctl reload-configuration
        stop hue
        start hue
    fi
}

##############################
if [ "$(id -u)" != "0" ]; then
    echo "[ERROR] The script has to be run as root."
    usage
fi

USERID=$(echo -e "import hdinsight_common.Constants as Constants\nprint Constants.AMBARI_WATCHDOG_USERNAME" | python)

echo "USERID=$USERID"

PASSWD=$(echo -e "import hdinsight_common.ClusterManifestParser as ClusterManifestParser\nimport hdinsight_common.Constants as Constants\nimport base64\nbase64pwd = ClusterManifestParser.parse_local_manifest().ambari_users.usersmap[Constants.AMBARI_WATCHDOG_USERNAME].password\nprint base64.b64decode(base64pwd)" | python)

export JAVA_HOME=/usr/lib/jvm/java-7-openjdk-amd64

if [ -e $HUE_INSTALLFOLDER ]; then
    echo "Hue is already installed. Exiting ..."
    exit 0
fi

if [[ $OS_VERSION == 14* ]]; then
    export JAVA_HOME=/usr/lib/jvm/java-7-openjdk-amd64
elif [[ $OS_VERSION == 16* ]]; then
    export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
fi

checkHostNameAndSetClusterName
validateUsernameAndPassword
updateAmbariConfigs
stopServiceViaRest HDFS
stopServiceViaRest YARN
stopServiceViaRest MAPREDUCE2
stopServiceViaRest OOZIE

echo "Download and unzip WebWasb and Hue while services are STOPPING"
downloadAndUnzipWebWasb
downloadAndUnzipHue

startServiceViaRest YARN
startServiceViaRest MAPREDUCE2
startServiceViaRest OOZIE
startServiceViaRest HDFS

setupWebWasbService
setupHueService

