#!/bin/bash          

user=$1
password=$2
tsd_listen_port=${3:-4242}
proxy_domain_suffix=$4
num_edge_nodes=${5:-1}

opentsdb_tar_file=OPENTSDB.tar.gz
opentsdb_tar_file_uri=https://github.com/hdinsight/Iaas-Applications/files/530759/$opentsdb_tar_file
detached_script_uri=https://raw.githubusercontent.com/hdinsight/Iaas-Applications/master/OpenTSDB/deployment/create-ambari-services.sh

echo "$(date +%T) Starting custom action script for provisioning OpenTSDB as an Ambari service"
apt-get -y install jq
wget https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64 -O /usr/bin/jq

cluster=$(curl -u $user:$password http://headnodehost:8080/api/v1/clusters | jq -r .items[0].Clusters.cluster_name)
stack_name=$(curl -u $user:$password http://headnodehost:8080/api/v1/clusters/$cluster/stack_versions | jq -r '.items[0].ClusterStackVersions.stack')
stack_version=$(curl -u $user:$password http://headnodehost:8080/api/v1/clusters/$cluster/stack_versions | jq -r '.items[0].ClusterStackVersions.version')
echo "$(date +%T) Cluster: $cluster, Stack: $stack_name-$stack_version" 

cd /var/lib/ambari-server/resources/stacks/$stack_name/$stack_version/services
wget "$opentsdb_tar_file_uri" -O /tmp/$opentsdb_tar_file
tar -xvf /tmp/$opentsdb_tar_file
chmod -R 644 OPENTSDB

# We have to enable the Ambari agents to pickup the new service artifacts
sed -i "s/\(agent.auto.cache.update=\).*/\1true/" /etc/ambari-server/conf/ambari.properties

# metrics - add our metrics to the whitelist & recycle the metrics collector
cat OPENTSDB/metrics.json | jq -r '.OPENTSDB_TSD.Component[0].metrics.default[].metric' >> /etc/ambari-metrics-collector/conf/whitelistedmetrics.txt
cat OPENTSDB/metrics.json | jq -r '.OPENTSDB_PROXY.Component[0].metrics.default[].metric' >> /etc/ambari-metrics-collector/conf/whitelistedmetrics.txt

# OPTIONAL - Install IFrame View to point to our edge node so that we get the OpenTSDB GUI hosted in Ambari Web App
if [ ! -z "$proxy_domain_suffix" ]; then
    edge_uri="https://$cluster-$proxy_domain_suffix.apps.azurehdinsight.net"
    echo "$(date +%T) Building IFrame View to point to edge node at address: $edge_uri"
    mkdir /tmp/opentsdb-view
    mkdir /tmp/opentsdb-view/jar
    mkdir /tmp/opentsdb-view/jar/META-INF
    cd /tmp/opentsdb-view/jar
    rm /tmp/opentsdb-view/opentsdb-view.jar
    # The order the we add things to the zip/jar is significant - manifest information must be first
    echo 'Manifest-Version: 1.0
Archiver-Version: Plexus Archiver
Created-By: Apache Maven
Built-By: root
Build-Jdk: 1.7.0_111

' > ./META-INF/MANIFEST.MF
    zip -r /tmp/opentsdb-view/opentsdb-view.jar META-INF 
    echo '
<html>
  <body>
    <iframe src="'$edge_uri'" style="border: 0; position:fixed; top:0; left:0; right:0; bottom:0; width:100%; height:100%">
  </body>
</html>
' > index.html
    echo '
<view>
  <name>OPENTSDB_VIEW</name>
  <label>OpenTSDB View</label>
  <version>1.0.0</version>
  <instance>
    <name>INSTANCE_1</name>
  </instance>
</view>
' > view.xml
    zip -r /tmp/opentsdb-view/opentsdb-view.jar *
    cp /tmp/opentsdb-view/opentsdb-view.jar /var/lib/ambari-server/resources/views
else

    num_edge_nodes=0
fi

# We need to determine if this is the active headnode
head_ip=$(getent hosts headnodehost | awk '{ print $1; exit }')
is_active_headnode=$(expr "$(hostname -i)" == "$head_ip")
echo "$(date +%T) This node is active headnode: $is_active_headnode"

echo "$(date +%T) Processing service registration on active head node via background script"
wget "$detached_script_uri" -O /tmp/create-opentsdb-ambari-services.sh
chmod 744 /tmp/create-opentsdb-ambari-services.sh
mkdir /var/log/opentsdb
echo "$(date +%T) Logging background activity to /var/log/opentsdb/create-ambari-services.out & /var/log/opentsdb/create-ambari-services.err"
nohup /tmp/create-opentsdb-ambari-services.sh $user $password $cluster $is_active_headnode $tsd_listen_port $num_edge_nodes >/var/log/opentsdb/create-ambari-services.out 2>/var/log/opentsdb/create-ambari-services.err &
echo "$(date +%T) OpenTSDB has been installed and TSD components have been deployed to all HBase region servers"



