#!/bin/bash          

# This script is a no-op script to be executed on edge nodes when deploying new services into Ambari. The detached
# script running on the headnodes are polling for this script to complete before continuing (they need to restart Ambari).
# We need to write the specified signature tag into the log, which will be detected by the headnode script as an indication
# that this edge node has been fully provisioned.

user=$1
password=$2
edgenode_script_tag=${3:-edgenode-signature-tag}

echo "$(date +%T) Starting custom action script for deploying edge node services"
apt-get -y install jq

cluster=$(curl -u $user:$password http://headnodehost:8080/api/v1/clusters | jq -r .items[0].Clusters.cluster_name)
edge_hostname=$(hostname -f)
echo "$(date +%T) Cluster: $cluster, Host: $edge_hostname"
# This tag is required so that the detached script running on the headnode can detect that the edge node script has completed
echo "$(date +%T) Tag: $edgenode_script_tag" 
echo "$(date +%T) Ambari service installation will be completed on active head node"
