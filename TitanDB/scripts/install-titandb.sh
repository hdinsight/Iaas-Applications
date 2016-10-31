#!/bin/bash          

user=$1
password=$2
titan_listen_port=${3:-4242}
edgenode_dns_suffix=$4
num_edge_nodes=${5:-1}
selected_topology=${6:-1}

titandb_ambari_svc_tar_file=TITANDB.tar.gz
titandb_ambari_svc_tar_file_uri=https://github.com/jamesbak/Iaas-Applications/files/530759/$titandb_ambari_svc_tar_file
detached_script_uri=https://raw.githubusercontent.com/jamesbak/Iaas-Applications/titandb/TitanDB/scripts/create-ambari-services.sh

echo "$(date +%T) Starting custom action script for provisioning TitanDB as an Ambari service"
apt-get -y install jq

cluster=$(curl -u $user:$password http://headnodehost:8080/api/v1/clusters | jq -r .items[0].Clusters.cluster_name)
stack_name=$(curl -u $user:$password http://headnodehost:8080/api/v1/clusters/$cluster/stack_versions | jq -r '.items[0].ClusterStackVersions.stack')
stack_version=$(curl -u $user:$password http://headnodehost:8080/api/v1/clusters/$cluster/stack_versions | jq -r '.items[0].ClusterStackVersions.version')
echo "$(date +%T) Cluster: $cluster, Stack: $stack_name-$stack_version" 

cd /var/lib/ambari-server/resources/stacks/$stack_name/$stack_version/services
wget "$titandb_ambari_svc_tar_file_uri" -O /tmp/$titandb_ambari_svc_tar_file
tar -xvf /tmp/$titandb_ambari_svc_tar_file
chmod -R 644 TITANDB

# We have to enable the Ambari agents to pickup the new service artifacts
sed -i "s/\(agent.auto.cache.update=\).*/\1true/" /etc/ambari-server/conf/ambari.properties

# OPTIONAL - Install IFrame View to point to our edge node so that we get the TitanDB GUI hosted in Ambari Web App
if [ ! -z "$edgenode_dns_suffix" ]; then
    edge_uri="https://$cluster-$edgenode_dns_suffix.apps.azurehdinsight.net"
    echo "$(date +%T) Building IFrame View to point to edge node at address: $edge_uri"
    mkdir /tmp/titandb-view
    mkdir /tmp/titandb-view/jar
    mkdir /tmp/titandb-view/jar/META-INF
    cd /tmp/titandb-view/jar
    rm /tmp/titandb-view/titandb-view.jar
    # The order the we add things to the zip/jar is significant - manifest information must be first
    echo 'Manifest-Version: 1.0
Archiver-Version: Plexus Archiver
Created-By: Apache Maven
Built-By: root
Build-Jdk: 1.7.0_111

' > ./META-INF/MANIFEST.MF
    zip -r /tmp/titandb-view/titandb-view.jar META-INF 
    echo '
<html>
  <body>
    <iframe src="'$edge_uri'" style="border: 0; position:fixed; top:0; left:0; right:0; bottom:0; width:100%; height:100%">
  </body>
</html>
' > index.html
    echo '
<view>
  <name>TITANDB_VIEW</name>
  <label>TitanDB View</label>
  <version>1.0.0</version>
  <instance>
    <name>INSTANCE_1</name>
  </instance>
</view>
' > view.xml
    zip -r /tmp/titandb-view/titandb-view.jar *
    cp /tmp/titandb-view/titandb-view.jar /var/lib/ambari-server/resources/views
else

    num_edge_nodes=0
fi

# We need to determine if this is the active headnode
head_ip=$(getent hosts headnodehost | awk '{ print $1; exit }')
is_active_headnode=$(expr "$(hostname -i)" == "$head_ip")
echo "$(date +%T) This node is active headnode: $is_active_headnode"

echo "$(date +%T) Processing service registration on active head node via background script"
wget "$detached_script_uri" -O /tmp/create-titandb-ambari-services.sh
chmod 744 /tmp/create-titandb-ambari-services.sh
mkdir /var/log/titandb
echo "$(date +%T) Logging background activity to /var/log/titandb/create-ambari-services.out & /var/log/titandb/create-ambari-services.err"
nohup /tmp/create-titandb-ambari-services.sh $user $password $cluster $is_active_headnode $titan_listen_port $num_edge_nodes $selected_topology>/var/log/titandb/create-ambari-services.out 2>/var/log/titandb/create-ambari-services.err &
echo "$(date +%T) TitanDB has been installed as Ambari service. Pending edge node provisioning prior to deployment."



