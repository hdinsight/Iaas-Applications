#!/bin/bash          

# This script originally took care of the installation of the external proxy host components OPENTSDB_PROXY, but since
# we have to defer restarting Ambari until AFTER the edge node(s) are fully provisioned, this script is now just a 
# placeholder that the detached script running on the active headnode is monitoring to detect completion.

user=$1
password=$2
edgenode_script_tag=${3:-edgenode-signature-tag}

echo "$(date +%T) Starting custom action script for deploying edge node load balancer proxy for TitanDB servers"
apt-get -y install jq

cluster=$(curl -u $user:$password http://headnodehost:8080/api/v1/clusters | jq -r .items[0].Clusters.cluster_name)
edge_hostname=$(hostname -f)
echo "$(date +%T) Cluster: $cluster, Host: $edge_hostname"
# This tag is required so that the detached script running on the headnode can detect that the edge node script has completed
echo "$(date +%T) Tag: $edgenode_script_tag" 
echo "$(date +%T) Proxy installation will be completed on active head node"
