#!/bin/bash          

# Shared set of functionality to register & install Ambari services on HDInsight cluster

# Name: get_cluster_stack_details
# Deetermine cluster name, stack name & stack version for the current Ambari cluster. 
# Parameters (in order):
#   1: ambari_user
#   2: ambari_password
# Outputs (globals assigned)
#   cluster (name of cluster)
#   stack_name (stack name. eg. HDP)
#   stack_version (current stack version. eg. 2.5)
function get_cluster_stack_details {

    local ambari_user=$1
    local ambari_password=$2

    cluster=$(curl -u $ambari_user:$ambari_password http://headnodehost:8080/api/v1/clusters | jq -r .items[0].Clusters.cluster_name)
    stack_name=$(curl -u $ambari_user:$ambari_password http://headnodehost:8080/api/v1/clusters/$cluster/stack_versions | jq -r '.items[0].ClusterStackVersions.stack')
    stack_version=$(curl -u $ambari_user:$ambari_password http://headnodehost:8080/api/v1/clusters/$cluster/stack_versions | jq -r '.items[0].ClusterStackVersions.version')
    log "Cluster: $cluster, Stack: $stack_name-$stack_version" 
}

# Name: install_ambari_service_tarball
# Downloads & unpacks the specified tar file that is the archive of the ambari service.
# MUST have previously called get_cluster_stack_details to initialize required variables 
# Parameters (in order):
#   1: service_name
#   2: service_tar_filename
#   3: service_tar_uri
function install_ambari_service_tarball {

    local service_name=$1
    local service_tar_filename=$2
    local service_tar_uri=$3

    cd /var/lib/ambari-server/resources/stacks/$stack_name/$stack_version/services
    wget "$service_tar_uri" -O /tmp/$service_tar_filename
    tar -xvf /tmp/$service_tar_filename
    chmod -R 644 $service_name
    # We have to enable the Ambari agents to pickup the new service artifacts
    sed -i "s/\(agent.auto.cache.update=\).*/\1true/" /etc/ambari-server/conf/ambari.properties
}

# Name: wait_for_edge_node_scripts
# Wait for all edge node placeholder scripts to be executed. This is detected by polling Ambari requests, looking for the 
# specified signature tag to be present in the output of the task. If this is not detected prior to timeout, the script is 
# fatally terminated.
# Parameters (in order):
#   1: ambari_user
#   2: ambari_password
#   3: ambari_cluster_name
#   4: num_edge_nodes (int)
#   5: edgenode_script_tag (default 'edgenode-signature-tag')
# Outputs (globals assigned)
#   edge_node_hosts (array of edge node hostnames)
function wait_for_edge_node_scripts {

    local ambari_user=$1
    local ambari_password=$2
    local ambari_cluster=$3
    local num_edge_nodes=$4
    local edgenode_script_tag=${5:-edgenode-signature-tag}

    # We defer the required reboot of Ambari - to make the TitanDB service effective, until after the entire cluster,
    # including edge nodes, have been fully deployed. 
    # To detect when the edge node(s) have been fully deployed, we watch for a request to 'run_customscriptaction' which
    # is the script action running on the edge nodes
    log "Waiting for the registration of $num_edge_nodes edge nodes"
    # Ambari time is ms
    local start_time=$(($(date +%s) * 1000))
    # Wait around for 30 mins
    local timeout_time=$(($(date +%s) + 30 * 60))
    edge_node_hosts=()
    while [[ ${#edge_node_hosts[@]} -lt $num_edge_nodes ]]; do
        edge_node_hosts=()
        custom_action_request_ids=$(curl -u $ambari_user:$ambari_password "http://headnodehost:8080/api/v1/clusters/$ambari_cluster/requests?fields=Requests/request_status&Requests/request_context=run_customscriptaction&Requests/create_time>$start_time" | jq -r '.items[] | select(.Requests.request_status == "COMPLETED") | .Requests.id')
        for id in $custom_action_request_ids; do
            local is_edge_node_request=$(curl -u $ambari_user:$ambari_password "http://headnodehost:8080/api/v1/clusters/$ambari_cluster/requests/$id/tasks?fields=Tasks/stdout" | jq '[.items[].Tasks.stdout | contains("'$edgenode_script_tag'") ] | all')
            if [[ $is_edge_node_request == true ]]; then
                local request_hosts=$(curl -u $ambari_user:$ambari_password "http://headnodehost:8080/api/v1/clusters/$ambari_cluster/requests/$id" | jq -r '.Requests.resource_filters[].hosts[]')
                for host in $request_hosts; do
                    edge_node_hosts+=($host)
                done
            fi
        done
        if [[ $(date +%s) -ge $timeout_time ]]; then
            log "FATAL: Timed out waiting for $num_edge_nodes edge nodes to be registered. Current registered hosts: ${edge_node_hosts[*]}"
            exit
        fi
        if [[ ${#edge_node_hosts[@]} -gt 0 ]]; then
            log "Completed edge node hosts: ${edge_node_hosts[*]}"
        fi
        sleep 3s
    done
}

# Name: install_component_on_hosts
# Install the specied host component on the specified hosts  
# Parameters (in order):
#   1: ambari_user
#   2: ambari_password
#   3: ambari_cluster_name
#   4: component_name
#   5: hosts (array of hostnames)
function install_component_on_hosts {

    local ambari_user=$1
    local ambari_password=$2
    local ambari_cluster=$3
    local component_name=$4
    shift 4
    local component_hosts=("$@")

    for host in ${component_hosts[@]}; do
        log "Installing $component_name component on host: $host"
        curl -u $ambari_user:$ambari_password -H "X-Requested-By:ambari" -X POST "http://headnodehost:8080/api/v1/clusters/$ambari_cluster/hosts/$host/host_components/$component_name"
    done
}    

# Name: deploy_ambari_service
# Installs all host components for the specified service  
# Parameters (in order):
#   1: ambari_user
#   2: ambari_password
#   3: ambari_cluster_name
#   4: service_name
function deploy_ambari_service {

    local ambari_user=$1
    local ambari_password=$2
    local ambari_cluster=$3
    local service_name=$4

    # install now & wait for the installation to complete
    log "Deploying all components for service: $service_name"
    local response=$(curl -u $ambari_user:$ambari_password -H "X-Requested-By:ambari" -X PUT -d '{"RequestInfo": {"context":"Install '$service_name' services"}, "Body": {"ServiceInfo": {"state": "INSTALLED"}}}' "http://headnodehost:8080/api/v1/clusters/$ambari_cluster/services/$service_name")
    local install_id=$(echo $response | jq -r '.Requests.id')
    if [[ $install_id ]]; then
        log "Install request id is: $install_id"
        local percent_complete=0
        local timeout_time=$(($(date +%s) + 5 * 60))
        while [ $percent_complete -lt 100 ]; do
            local complete=$(curl -u $ambari_user:$ambari_password -H "X-Requested-By:ambari" "http://headnodehost:8080/api/v1/clusters/$ambari_cluster/requests/$install_id" | jq -r '.Requests.progress_percent')
            local percent_complete=$(printf "%.0f" $complete)
            log "Install completion percentage: $percent_complete"
            if [[ $(date +%s) -ge $timeout_time ]]; then
                log "FATAL: Timed out waiting for $service_name components to install."
                break
            fi
            sleep 3s
        done
    else

        log "FATAL: Installation of $service_name components failed. Details: $response"
    fi
}

# Name: is_active_headnode
# Determines if the current node is the active headnode by comparing IP address with 'headnodehost'
# Returns (retrieve via $?):
#   0: Current node is NOT active headnode
#   1: Current node IS active headnode
function is_active_headnode {
    local head_ip=$(getent hosts headnodehost | awk '{ print $1; exit }')
    local active_headnode=$(expr "$(hostname -i)" == "$head_ip")
    log "This node is active headnode: $active_headnode"
    return $active_headnode
}

# Name: create_service_iframe_view
# Constructs an Ambari View JAR file which is simply an IFrame hosted within Ambari's web app pointing to the website at the edge node's HTTPS endpoint  
# Parameters (in order):
#   1: cluster
#   2: edgenode_dns_suffix 
#   3: view_name 
#   4: view_description
function create_service_iframe_view {

    local cluster=$1
    local edgenode_dns_suffix=$2
    local view_name=$3
    local view_description=$4

    local edge_uri="https://$cluster-$edgenode_dns_suffix.apps.azurehdinsight.net"
    local jar_basedir="/tmp/$view_name"
    local jar_filename="$jar_basedir/$view_name.jar"
    log "Building IFrame View to point to edge node at address: $edge_uri"
    mkdir "$jar_basedir"
    mkdir "$jar_basedir/jar"
    mkdir "$jar_basedir/jar/META-INF"
    cd "$jar_basedir/jar"
    rm $jar_filename
    # The order the we add things to the zip/jar is significant - manifest information must be first
    echo 'Manifest-Version: 1.0
Archiver-Version: Plexus Archiver
Created-By: Apache Maven
Built-By: root
Build-Jdk: 1.7.0_111

' > ./META-INF/MANIFEST.MF
    zip -r $jar_filename META-INF 
    echo '
<html>
  <body>
    <iframe src="'$edge_uri'" style="border: 0; position:fixed; top:0; left:0; right:0; bottom:0; width:100%; height:100%">
  </body>
</html>
' > index.html
    echo '
<view>
  <name>'$view_name'</name>
  <label>'$view_description'</label>
  <version>1.0.0</version>
  <instance>
    <name>INSTANCE_1</name>
  </instance>
</view>
' > view.xml
    zip -r $jar_filename *
    cp $jar_filename /var/lib/ambari-server/resources/views
}

# Name: make_ambari_service_effective
# Performs all operations necessary (ie. restart) to register new service with Ambari
# Parameters:
#   1: service_name
function make_ambari_service_effective {

    local service_name=$1

    log "Proceeding with registration & installation of $service_name service + components on head node"
    sleep 30s
    log "Restarting Ambari on head node to register $service_name service"
    ambari-server refresh-stack-hash
    service ambari-server restart
    # We have to wait for it to come back up properly 
    sleep 45s
}

# Name: launch_detached_install_script
# Download & run detached script that will complete registration & installation of Ambari service AFTER HDI has completed it's provisioning.
# This is required due to the fact that we need to restart Ambari to register a new service, but HDI is relying on Ambari being continuously
# running to complete it's provisioning.
# Parameters (in order)
#   1: ambari_user 
#   2: ambari_password 
#   3: ambari_cluster 
#   4: active_headnode 
#   5: num_edge_nodes 
#   6: edgenode_script_tag 
#   7: detached_script_uri 
#   8: detached_script_filename
#   9: script_log_dir (relative to /var/log/)
#   others: any script-specific arguments
function launch_detached_install_script {

    local ambari_user=$1
    local ambari_password=$2
    local ambari_cluster=$3
    local active_headnode=$4 
    local num_edge_nodes=$5 
    local edgenode_script_tag=$6 
    local detached_script_uri=$7 
    local detached_script_filename=$8
    local script_log_dir=$9
    shift 9

    log "Processing service registration on head node via background script"
    local script_file="/tmp/$detached_script_filename.sh"
    local logdir="/var/log/$script_log_dir"
    wget "$detached_script_uri" -O $script_file
    chmod +x $script_file
    mkdir $logdir
    log "Logging background activity to $logdir/$detached_script_filename.out & $logdir/$detached_script_filename.err"
    nohup $script_file $ambari_user $ambari_password $ambari_cluster $active_headnode $num_edge_nodes $edgenode_script_tag $@ > $logdir/$detached_script_filename.out 2> $logdir/$detached_script_filename.err &
}

# Name: restart_ams_if_necessary
# Restarts the Ambari Metrics Service collector service if the service is running on this host. This is required to make any new metrics registered in the whitelist file effective.
# Parameters (in order)
#   1: ambari_user 
#   2: ambari_password 
#   3: ambari_cluster 
function restart_ams_if_necessary {

    local ambari_user=$1
    local ambari_password=$2
    local ambari_cluster=$3

    local ams_collector_host=$(curl -u $ambari_user:$ambari_password "http://headnodehost:8080/api/v1/clusters/$ambari_cluster/services/AMBARI_METRICS/components/METRICS_COLLECTOR?fields=host_components" | jq -r '.host_components[0].HostRoles.host_name')
    if [[ $(hostname -f) == $ams_collector_host ]]; then
        log "Restarting AMS to make new whitelist metrics effective"
        su - ams -c'/usr/sbin/ambari-metrics-collector --config /etc/ambari-metrics-collector/conf/ restart'
    fi
}

# Name: log
# Echo supplied message with timestamp to stdout
# Parameters:
#   1: message
function log {
    echo "$(date +%T) $1"
}

