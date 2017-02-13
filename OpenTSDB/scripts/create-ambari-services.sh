#!/bin/bash          

# Script run nohup on the active head node only to provision & deploy OpenTSDB services via Ambari

user=$1
password=$2
cluster=$3
is_active_headnode=$4
tsd_listen_port=${5:-4242}
num_edge_nodes=${6:-0}

# Determine if AMS collector is running on this node (not necessarily the active headnode)
ams_collector_host=$(curl -u $user:$password "http://headnodehost:8080/api/v1/clusters/$cluster/services/AMBARI_METRICS/components/METRICS_COLLECTOR?fields=host_components" | jq -r '.host_components[0].HostRoles.host_name')

if [[ $(hostname -f) == $ams_collector_host ]]; then
    echo "$(date +%T) Restarting AMS to make new whitelist metrics effective"
    su - ams -c'/usr/sbin/ambari-metrics-collector --config /etc/ambari-metrics-collector/conf/ restart'
fi

# We only need the service registration to proceed once - do it on the active headnode
if [[ $is_active_headnode ]]; then
    # We defer the required reboot of Ambari - to make the OpenTSDB service effective, until after the entire cluster,
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

    echo "$(date +%T) Proceeding with registration & installation of OpenTSDB service + components on active head node"
    sleep 30s
    echo "$(date +%T) Restarting Ambari on active namenode to register OpenTSDB service"
    ambari-server refresh-stack-hash
    service ambari-server restart
    
    # We have to wait for it to come back up properly 
    sleep 45s

    echo "$(date +%T) Registering OpenTSDB service with Ambari"
    curl -u $user:$password -H "X-Requested-By:ambari" -X POST -d '{"ServiceInfo":{"service_name":"OPENTSDB"}}' "http://headnodehost:8080/api/v1/clusters/$cluster/services"
    curl -u $user:$password -H "X-Requested-By:ambari" -X POST "http://headnodehost:8080/api/v1/clusters/$cluster/services/OPENTSDB/components/OPENTSDB_TSD"
    curl -u $user:$password -H "X-Requested-By:ambari" -X POST "http://headnodehost:8080/api/v1/clusters/$cluster/services/OPENTSDB/components/OPENTSDB_PROXY"
    config_tag=INITIAL
    curl -u $user:$password -H "X-Requested-By:ambari" -X POST -d '{"type": "opentsdb-site", "tag": "'$config_tag'", "properties" : {
            "tsd.network.port" : "'$tsd_listen_port'",
            "tsd.core.auto_create_metrics" : "true",
            "tsd.http.cachedir" : "/tmp/opentsdb",
            "tsd.http.staticroot" : "/usr/share/opentsdb/static/",
            "tsd.network.async_io" : "true",
            "tsd.network.keep_alive" : "true",
            "tsd.network.reuse_address" : "true",
            "tsd.network.tcp_no_delay" : "true",
            "tsd.storage.enable_compaction" : "true",
            "tsd.storage.flush_interval" : "1000",
            "tsd.storage.hbase.data_table" : "tsdb",
            "tsd.storage.hbase.uid_table" : "tsdb-uid"
        }}' "http://headnodehost:8080/api/v1/clusters/$cluster/configurations"
    curl -u $user:$password -H "X-Requested-By:ambari" -X POST -d '{"type": "opentsdb-config", "tag": "'$config_tag'", "properties" : {
            "opentsdb.create_schema" : "true",
            "opentsdb.opentsdb_version" : "2.2.0"
        }}' "http://headnodehost:8080/api/v1/clusters/$cluster/configurations"
    curl -u $user:$password -H "X-Requested-By:ambari" -X PUT -d '{"Clusters":{"desired_config" : {"type": "opentsdb-site", "tag": "'$config_tag'"}}}' "http://headnodehost:8080/api/v1/clusters/$cluster"
    curl -u $user:$password -H "X-Requested-By:ambari" -X PUT -d '{"Clusters":{"desired_config" : {"type": "opentsdb-config", "tag": "'$config_tag'"}}}' "http://headnodehost:8080/api/v1/clusters/$cluster"

    # deploy TSD component to all Region Server nodes
    echo "$(date +%T) Installing OpenTSDB TSD component on all HBase region servers"
    region_hosts=$(curl -u $user:$password -H "X-Requested-By:ambari" "http://headnodehost:8080/api/v1/clusters/$cluster/services/HBASE/components/HBASE_REGIONSERVER?fields=host_components" | jq -r '.host_components[].HostRoles.host_name')
    for host in $region_hosts; do
        echo "$(date +%T) Installing OpenTSDB TSD component on host: $host"
        curl -u $user:$password -H "X-Requested-By:ambari" -X POST "http://headnodehost:8080/api/v1/clusters/$cluster/hosts/$host/host_components/OPENTSDB_TSD"
    done

    # deploy proxy component to all edge nodes
    echo "$(date +%T) Installing OpenTSDB proxy component on all edge nodes"
    for host in ${registered_hosts[@]}; do
        echo "$(date +%T) Installing OpenTSDB proxy component on host: $host"
        curl -u $user:$password -H "X-Requested-By:ambari" -X POST "http://headnodehost:8080/api/v1/clusters/$cluster/hosts/$host/host_components/OPENTSDB_PROXY"
    done

    # install now & wait for the installation to complete
    response=$(curl -u $user:$password -H "X-Requested-By:ambari" -X PUT -d '{"RequestInfo": {"context":"Install OPENTSDB daemon services"}, "Body": {"ServiceInfo": {"state": "INSTALLED"}}}' "http://headnodehost:8080/api/v1/clusters/$cluster/services/OPENTSDB")
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
                echo "$(date +%T) Timed out waiting for OpenTSDB components to install."
                break
            fi
            sleep 3s
        done

        # finally, start the service
        echo "$(date +%T) Starting the OpenTSDB TSD service on all hosts"
        curl -u $user:$password -H "X-Requested-By:ambari" -X PUT -d '{"RequestInfo": {"context":"Start OPENTSDB services"}, "Body": {"ServiceInfo": {"state": "STARTED"}}}' "http://headnodehost:8080/api/v1/clusters/$cluster/services/OPENTSDB"
    else

        echo "$(date +%T) FATAL: Installation of OpenTSDB components failed. Details: $response"
    fi
else

    # Restart Ambari to cause our new service artifacts to be registered
    echo "$(date +%T) Restarting Ambari on standby namenode to register OpenTSDB service"
    ambari-server refresh-stack-hash
    service ambari-server restart
fi
echo "$(date +%T) Completed secondary installation of OpenTSDB service"
