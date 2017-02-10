#!/usr/bin/python

import os, os.path, sys, imp, datetime
import requests
import resource_management

def log(msg):
    now = datetime.now()
    print now.strftime('%H:%M:%S') + ' ' + msg

def get_cluster_stack_details(ambari_user, ambari_password):
    cluster = requests.get('http://headnodehost:8080/api/v1/clusters', auth=(ambari_user, ambari_password)).json()['items'][0]['Clusters']['cluster_name']

    cluster=$(curl -u $ambari_user:$ambari_password http://headnodehost:8080/api/v1/clusters | jq -r .items[0].Clusters.cluster_name)
    stack_name=$(curl -u $ambari_user:$ambari_password http://headnodehost:8080/api/v1/clusters/$cluster/stack_versions | jq -r '.items[0].ClusterStackVersions.stack')
    stack_version=$(curl -u $ambari_user:$ambari_password http://headnodehost:8080/api/v1/clusters/$cluster/stack_versions | jq -r '.items[0].ClusterStackVersions.version')
    log "Cluster: $cluster, Stack: $stack_name-$stack_version" 
    

