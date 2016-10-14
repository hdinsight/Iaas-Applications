#!/bin/bash          

# This script originally took care of the installation of the external proxy host components OPENTSDB_PROXY, but since
# we have to defer restarting Ambari until AFTER the edge node(s) are fully provisioned, this script is now just a 
# placeholder that the detached script running on the active headnode is monitoring to detect completion.

user=$1
password=$2

echo "$(date +%T) Starting custom action script for deploying edge node proxy for TSD servers"
apt-get install jq
wget https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64 -O /usr/bin/jq

cluster=$(curl -u $user:$password http://headnodehost:8080/api/v1/clusters | jq -r .items[0].Clusters.cluster_name)
edge_hostname=$(hostname -f)
echo "$(date +%T) Cluster: $cluster, Host: $edge_hostname" 
echo "$(date +%T) Proxy installation will be completed on active head node"
