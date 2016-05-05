#Install WebWasb
WEBWASB_TARFILE=webwasb-tomcat.tar.gz
WEBWASB_TARFILEURI=https://hdiconfigactions.blob.core.windows.net/linuxhueconfigactionv01/$WEBWASB_TARFILE
WEBWASB_TMPFOLDER=/tmp/webwasb
WEBWASB_INSTALLFOLDER=/usr/share/webwasb-tomcat

export JAVA_HOME=/usr/lib/jvm/java-7-openjdk-amd64

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

echo "Adding webwasb user"
useradd -r webwasb

echo "Making webwasb a service and start it"
sed -i "s|JAVAHOMEPLACEHOLDER|$JAVA_HOME|g" $WEBWASB_INSTALLFOLDER/upstart/webwasb.conf
chown -R webwasb:webwasb $WEBWASB_INSTALLFOLDER

cp -f $WEBWASB_INSTALLFOLDER/upstart/webwasb.conf /etc/init/
initctl reload-configuration
stop webwasb
start webwasb

#WebWasb takes a little bit of time to start up.
sleep 20