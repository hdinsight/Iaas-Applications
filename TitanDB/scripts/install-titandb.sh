#!/bin/bash          

user=$1
password=$2
titan_listen_port=${3:-8182}
edgenode_dns_suffix=$4
num_edge_nodes=${5:-1}
edgenode_script_tag=${6:-edgenode-signature-tag}
selected_topology=${7:-1}

titandb_ambari_svc_tar_file=TITANDB.tar.gz
titandb_ambari_svc_tar_file_uri=https://github.com/jamesbak/Iaas-Applications/files/570224/$titandb_ambari_svc_tar_file
detached_script_uri=https://raw.githubusercontent.com/jamesbak/Iaas-Applications/titandb/TitanDB/scripts/create-ambari-services.sh
shared_lib_script_uri=https://raw.githubusercontent.com/jamesbak/Iaas-Applications/titandb/Scripts/shared-ambari-installation.sh
shared_lib_script_loc=/tmp/shared-ambari-installation.sh

wget $shared_lib_script_uri -O $shared_lib_script_loc
chmod +x $shared_lib_script_loc
source $shared_lib_script_loc

log "Starting custom action script for provisioning TitanDB as an Ambari service"
apt-get -y install jq

get_cluster_stack_details $user $password
install_ambari_service_tarball "TITANDB" $titandb_ambari_svc_tar_file $titandb_ambari_svc_tar_file_uri 

# OPTIONAL - Install IFrame View to point to our edge node so that we get the TitanDB GUI hosted in Ambari Web App
if [ ! -z "$edgenode_dns_suffix" ]; then
    create_service_iframe_view $cluster $edgenode_dns_suffix "titandb-view" "TitanDB View" 
else
    num_edge_nodes=0
fi

# We need to determine if this is the active headnode
is_active_headnode
active_headnode=$?

launch_detached_install_script $user $password $cluster $active_headnode $num_edge_nodes $edgenode_script_tag $detached_script_uri "create-titandb-ambari-services" "titandb" $titan_listen_port $selected_topology  
log "TitanDB has been installed as Ambari service. Pending edge node provisioning prior to deployment."

