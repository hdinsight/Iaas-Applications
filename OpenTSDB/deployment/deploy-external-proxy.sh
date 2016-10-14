#!/bin/bash          

user=$1
password=$2

echo "$(date +%T) Starting custom action script for deploying edge node proxy for TSD servers"
apt-get install jq
wget https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64 -O /usr/bin/jq

cluster=$(curl -u $user:$password http://headnodehost:8080/api/v1/clusters | jq -r .items[0].Clusters.cluster_name)
edge_hostname=$(hostname -f)
echo "$(date +%T) Cluster: $cluster, Host: $edge_hostname" 
echo "$(date +%T) Proxy installation will be completed on active head node"
