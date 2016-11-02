#!/bin/bash          

# Script run nohup on the active head node only to provision & deploy TitanDB services via Ambari

user=$1
password=$2
cluster=$3
is_active_headnode=$4
titan_listen_port=${5:-8182}
num_edge_nodes=${6:-0}
selected_topology=${6:-1}

# Determine if AMS collector is running on this node (not necessarily the active headnode)
ams_collector_host=$(curl -u $user:$password "http://headnodehost:8080/api/v1/clusters/$cluster/services/AMBARI_METRICS/components/METRICS_COLLECTOR?fields=host_components" | jq -r '.host_components[0].HostRoles.host_name')

if [[ $(hostname -f) == $ams_collector_host ]]; then
    echo "$(date +%T) Restarting AMS to make new whitelist metrics effective"
    su - ams -c'/usr/sbin/ambari-metrics-collector --config /etc/ambari-metrics-collector/conf/ restart'
fi

# We only need the service registration to proceed once - do it on the active headnode
if [[ $is_active_headnode ]]; then
    # We defer the required reboot of Ambari - to make the TitanDB service effective, until after the entire cluster,
    # including edge nodes, have been fully deployed. 
    # To detect when the edge node(s) have been fully deployed, we watch for a request to 'run_customscriptaction' which
    # is the script action running on the edge nodes
    echo "$(date +%T) Waiting for the registration of $num_edge_nodes edge nodes"
    start_time=$(($(date +%s) * 1000))
    # Wait around for 30 mins
    timeout_time=$(($(date +%s) + 30 * 60))
    registered_hosts=()
    while [[ ${#registered_hosts[@]} -lt $num_edge_nodes ]]; do
        registered_hosts=()
        custom_action_request_ids=$(curl -u $user:$password "http://headnodehost:8080/api/v1/clusters/$cluster/requests?Requests/request_context=run_customscriptaction&Requests/create_time>$start_time" | jq -r '.items[].Requests.id')
        for id in $custom_action_request_ids; do
            request_hosts=$(curl -u $user:$password "http://headnodehost:8080/api/v1/clusters/$cluster/requests/$id" | jq -r 'select(.Requests.request_status == "COMPLETED") | .Requests.resource_filters[].hosts[]')
            for host in $request_hosts; do
                registered_hosts+=($host)
            done
        done
        if [[ $(date +%s) -ge $timeout_time ]]; then
            echo "$(date +%T) FATAL: Timed out waiting for $num_edge_nodes edge nodes to be registered. Current registered hosts: ${registered_hosts[*]}"
            exit
        fi
        if [[ ${#registered_hosts[@]} -gt 0 ]]; then
            echo "$(date +%T) Completed edge node hosts: ${registered_hosts[*]}"
        fi
        sleep 3s
    done

    echo "$(date +%T) Proceeding with registration & installation of TitanDB service + components on active head node"
    sleep 30s
    echo "$(date +%T) Restarting Ambari on active namenode to register TitanDB service"
    ambari-server refresh-stack-hash
    service ambari-server restart
    
    # We have to wait for it to come back up properly 
    sleep 45s

    echo "$(date +%T) Registering TitanDB service with Ambari"
    curl -u $user:$password -H "X-Requested-By:ambari" -X POST -d '{"ServiceInfo":{"service_name":"TITANDB"}}' "http://headnodehost:8080/api/v1/clusters/$cluster/services"
    curl -u $user:$password -H "X-Requested-By:ambari" -X POST "http://headnodehost:8080/api/v1/clusters/$cluster/services/TITANDB/components/TITANDB_SERVER"
    curl -u $user:$password -H "X-Requested-By:ambari" -X POST "http://headnodehost:8080/api/v1/clusters/$cluster/services/TITANDB/components/TITANDB_PROXY"
    config_tag=INITIAL
    curl -u $user:$password -H "X-Requested-By:ambari" -X POST -d '{"type": "titandb-site", "tag": "'$config_tag'", "properties" : {
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
        }}' "http://headnodehost:8080/api/v1/clusters/$cluster/configurations"
    curl -u $user:$password -H "X-Requested-By:ambari" -X PUT -d '{"Clusters":{"desired_config" : {"type": "titandb-site", "tag": "'$config_tag'"}}}' "http://headnodehost:8080/api/v1/clusters/$cluster"

    # We have 2 supported topologies:
    #   1. TitanDB deployed to edge node(s) only
    #   2. TitanDB deployed to every region server & load balanced from edge node
    if [[ $selected_topology == 2 ]]; then
        region_hosts=$(curl -u $user:$password -H "X-Requested-By:ambari" "http://headnodehost:8080/api/v1/clusters/$cluster/services/HBASE/components/HBASE_REGIONSERVER?fields=host_components" | jq -r '.host_components[].HostRoles.host_name')
        IFS=' ' read -r -a server_hosts <<< $region_hosts
    else
        server_hosts=(${registered_hosts[@]})
    fi
    echo "$(date +%T) Installing TitanDB Server component"
    for host in ${server_hosts[@]}; do
        echo "$(date +%T) Installing TitanDB Server component on host: $host"
        curl -u $user:$password -H "X-Requested-By:ambari" -X POST "http://headnodehost:8080/api/v1/clusters/$cluster/hosts/$host/host_components/TITANDB_SERVER"
    done

    # deploy proxy component to all edge nodes if selected topology
    if [[ $selected_topology == 2 ]]; then
        echo "$(date +%T) Installing TitanDB proxy component on all edge nodes"
        for host in ${registered_hosts[@]}; do
            echo "$(date +%T) Installing TitanDB proxy component on host: $host"
            curl -u $user:$password -H "X-Requested-By:ambari" -X POST "http://headnodehost:8080/api/v1/clusters/$cluster/hosts/$host/host_components/TITANDB_PROXY"
        done
    fi

    # install now & wait for the installation to complete
    response=$(curl -u $user:$password -H "X-Requested-By:ambari" -X PUT -d '{"RequestInfo": {"context":"Install TITANDB daemon services"}, "Body": {"ServiceInfo": {"state": "INSTALLED"}}}' "http://headnodehost:8080/api/v1/clusters/$cluster/services/TITANDB")
    install_id=$(echo $response | jq -r '.Requests.id')
    if [[ $install_id != null ]]; then
        echo "$(date +%T) Install request id is: $install_id"
        percent_complete=0
        timeout_time=$(($(date +%s) + 5 * 60))
        while [ $percent_complete -lt 100 ]; do
            complete=$(curl -u $user:$password -H "X-Requested-By:ambari" "http://headnodehost:8080/api/v1/clusters/$cluster/requests/$install_id" | jq -r '.Requests.progress_percent')
            percent_complete=$(printf "%.0f" $complete)
            echo "$(date +%T) Install completion percentage: $percent_complete"
            if [[ $(date +%s) -ge $timeout_time ]]; then
                echo "$(date +%T) Timed out waiting for TitanDB components to install."
                break
            fi
            sleep 3s
        done

        # finally, start the service
        echo "$(date +%T) Starting the TitanDB TSD service on all hosts"
        curl -u $user:$password -H "X-Requested-By:ambari" -X PUT -d '{"RequestInfo": {"context":"Start TITANDB services"}, "Body": {"ServiceInfo": {"state": "STARTED"}}}' "http://headnodehost:8080/api/v1/clusters/$cluster/services/TITANDB"
    else

        echo "$(date +%T) FATAL: Installation of TitanDB components failed. Details: $response"
    fi
else

    # Restart Ambari to cause our new service artifacts to be registered
    echo "$(date +%T) Restarting Ambari on standby namenode to register TitanDB service"
    ambari-server refresh-stack-hash
    service ambari-server restart
fi
echo "$(date +%T) Completed secondary installation of TitanDB service"
