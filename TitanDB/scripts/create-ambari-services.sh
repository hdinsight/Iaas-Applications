#!/bin/bash          

# Script run nohup on the head node to provision & deploy TitanDB services via Ambari
# This script is invoked by calling shared-ambari-installation.sh/launch_detached_install_script - see notes on fixed & variable arguments 

source /tmp/shared-ambari-installation.sh

user=$1
password=$2
cluster=$3
active_headnode=$4
num_edge_nodes=${5:-0}
edgenode_script_tag=${6:-titandb-edgenode-signature-tag}
titan_listen_port=${7:-8182}
selected_topology=${8:-1}

# Determine if AMS collector is running on this node (not necessarily the active headnode)
restart_ams_if_necessary $user $password $cluster

# We only need the service registration to proceed once - do it on the active headnode
if [[ $active_headnode ]]; then
    # We defer the required reboot of Ambari - to make the TitanDB service effective, until after the entire cluster
    wait_for_edge_node_scripts $user $password $cluster $num_edge_nodes $edgenode_script_tag
    # HDI provisioning is complete - we can restart Ambari now
    make_ambari_service_effective "TitanDB"

    log "Registering TitanDB service with Ambari"
    curl -u $user:$password -H "X-Requested-By:ambari" -X POST -d '{"ServiceInfo":{"service_name":"TITANDB"}}' "http://headnodehost:8080/api/v1/clusters/$cluster/services"
    curl -u $user:$password -H "X-Requested-By:ambari" -X POST "http://headnodehost:8080/api/v1/clusters/$cluster/services/TITANDB/components/TITANDB_SERVER"
    curl -u $user:$password -H "X-Requested-By:ambari" -X POST "http://headnodehost:8080/api/v1/clusters/$cluster/services/TITANDB/components/TITANDB_PROXY"
    config_tag=INITIAL
    curl -u $user:$password -H "X-Requested-By:ambari" -X POST -d '{"type": "titandb-site", "tag": "'$config_tag'", 
        "properties" : {
            "storage.backend" : "hbase",
            "cache.db-cache" : "true",
            "cache.db-cache-clean-wait" : 20,
            "cache.db-cache-time" : 180000,
            "cache.db-cache-size" : 0.5,
            "index.search.backend" : "elasticsearch",
            "index.search.hostname" : "localhost",
            "index.search.elasticsearch.client-only" : "true",
            "storage.hbase.tablename" : "titan",
            "server.port" : '$titan_listen_port' 
        },
        "properties_attributes" : {
            "final" : {
                "index.search.hostname" : "true",
                "index.search.elasticsearch.client-only" : "true",
                "server.port" : "true",
                "cache.db-cache-size" : "true",
                "cache.db-cache-clean-wait" : "true",
                "cache.db-cache-time" : "true",
                "index.search.backend" : "true",
                "storage.hbase.tablename" : "true"
                }
            }
        }' "http://headnodehost:8080/api/v1/clusters/$cluster/configurations"
    curl -u $user:$password -H "X-Requested-By:ambari" -X PUT -d '{"Clusters":{"desired_config" : {"type": "titandb-site", "tag": "'$config_tag'"}}}' "http://headnodehost:8080/api/v1/clusters/$cluster"

    # We have 2 supported topologies:
    #   1. TitanDB deployed to edge node(s) only
    #   2. TitanDB deployed to every region server & load balanced from edge node
    if [[ $selected_topology -eq 2 ]]; then
        region_hosts=$(curl -u $user:$password -H "X-Requested-By:ambari" "http://headnodehost:8080/api/v1/clusters/$cluster/services/HBASE/components/HBASE_REGIONSERVER?fields=host_components" | jq -r '.host_components[].HostRoles.host_name')
        IFS=' ' read -r -a server_hosts <<< $region_hosts
    else
        server_hosts=(${edge_node_hosts[@]})
    fi
    log "Installing TitanDB Server component using topology: $selected_topology"
    primary_server_host=${server_hosts[0]}
    install_component_on_hosts $user $password $cluster "TITANDB_SERVER" ${server_hosts[@]}

    # deploy proxy component to all edge nodes if selected topology
    if [[ $selected_topology -eq 2 ]]; then
        install_component_on_hosts $user $password $cluster "TITANDB_PROXY" ${edge_node_hosts[@]}
    fi
    sleep 5s

    # install now & wait for the installation to complete
    deploy_ambari_service $user $password $cluster "TITANDB"
    # Start 1 instance of the TitanDB server initially to avoid potential race condition as mutliple server instances attempt to create the HBase tables concurrently
    log "Starting primary TitanDB server to create HBase tables..."
    curl -u $user:$password -H "X-Requested-By:ambari" -X PUT -d '{"RequestInfo": {"context":"Start TitanDB Server"}, "Body": {"HostRoles": {"state": "STARTED"}}}' "http://headnodehost:8080/api/v1/clusters/$cluster/hosts/$primary_server_host/host_components/TITANDB_SERVER"
    sleep 10s

    # finally, start the service
    log "Starting the TitanDB service on all hosts"
    curl -u $user:$password -H "X-Requested-By:ambari" -X PUT -d '{"RequestInfo": {"context":"Start TITANDB services"}, "Body": {"ServiceInfo": {"state": "STARTED"}}}' "http://headnodehost:8080/api/v1/clusters/$cluster/services/TITANDB"
else

    # Restart Ambari to cause our new service artifacts to be registered
    make_ambari_service_effective "TitanDB"
fi
log "Completed asynchronous installation of TitanDB service"
