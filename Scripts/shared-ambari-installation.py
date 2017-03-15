from ambariclient.client import Ambari
sys.path.append('/usr/lib/ambari-server/lib')
from resource_management import *
import time, urllib, tarfile, os, sys, stat, socket

# Shared set of functionality to register & install Ambari services on HDInsight cluster

class shared-ambari-installation:
    
    stack_name = None
    stack_version = None
    

    def _init_():
        client = Ambari('headnodehost', 8080, username, password)

    # Name: get_cluster_stack_details
    # Deetermine cluster name, stack name & stack version for the current Ambari cluster. 
    # Parameters (in order):
    #   1: ambari_user
    #   2: ambari_password
    # Outputs (globals assigned)
    #   cluster (name of cluster)
    #   stack_name (stack name. eg. HDP)
    #   stack_version (current stack version. eg. 2.5)
    def get_cluster_stack_details(self, username, password):
        cluster = self.client.clusters.next().cluster_name
        self.stack_name = client.stacks.next().stack_name
        self.stack_version = client.stacks(stack_name).versions.next().stack_version
        log("Cluster: ",cluster,", Stack: ",stack_name,"-",stack_version)


    # Name: install_ambari_service_tarball
    # Downloads & unpacks the specified tar file that is the archive of the ambari service.
    # MUST have previously called get_cluster_stack_details to initialize required variables 
    # Parameters (in order):
    #   1: service_name
    #   2: service_tar_filename
    #   3: service_tar_uri
    def install_ambari_service_tarball(service_name, service_tar_filename, service_tar_uri):
        urllib.urlretrieve(service_tar_uri,'/tmp/'+service_tar_filename)
        tar = tarfile.open('/tmp/'+service_tar_filename)
        tar.extractall('/var/lib/ambari-server/resources/stacks/'+stack_name+'/'+stack_version+'/services')
        os.chmod('/var/lib/ambari-server/resources/stacks/'+stack_name+'/'+stack_version+'/services/'+service_name, stat.S_IWRITE)
        os.chmod('/var/lib/ambari-server/resources/stacks/'+stack_name+'/'+stack_version+'/services/'+service_name, stat.S_IREAD)
        os.chmod('/var/lib/ambari-server/resources/stacks/'+stack_name+'/'+stack_version+'/services/'+service_name, stat.S_IRUSR)
        os.chmod('/var/lib/ambari-server/resources/stacks/'+stack_name+'/'+stack_version+'/services/'+service_name, stat.S_IRGRP)

        # We have to enable the Ambari agents to pickup the new service artifacts
        with Environment() as env:
            ModifyPropertiesFile('/etc/ambari-server/conf/ambari.properties', properties={'agent.auto.cache.update':'true'})



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
    def wait_for_edge_node_scripts(ambari_user, ambari_password, ambari_cluster_name, num_edge_nodes, edgenode_script_tag):
        # We defer the required reboot of Ambari - to make the TitanDB service effective, until after the entire cluster,
        # including edge nodes, have been fully deployed. 
        # To detect when the edge node(s) have been fully deployed, we watch for a request to 'run_customscriptaction' which
        # is the script action running on the edge nodes
        log("Waiting for the registration of ",num_edge_nodes," edge nodes")
        # Ambari time is ms
        start_time = int(round(time.time() * 1000))
        # Wait around for 30 mins
        timeout_time = int(round(time.time() + 30*60))
        client = Ambari('headnodehost', 8080, ambari_user, ambari_password)
        edge_node_hosts = []
        while len(edge_node_hosts) < num_edge_nodes:
            edge_node_hosts = []
            custom_action_requests = client.clusters(ambari_cluster_name).requests
            for req in custom_action_requests:
                if req.request_context == "run_customscriptaction" and req.create_time > start_time and req.request_status == "COMPLETED":
                    tasks = client.clusters(ambari_cluster_name).requests(req.id).tasks
                    for task in tasks:
                        if edgenode_script_tag in task.stdout:
                            request_hosts = client.clusters(ambari_cluster_name).requests(req.id).resource_filters
                            for hosts in request_hosts:
                                for host in hosts['hosts']:
                                    edge_node_hosts.append(host)
            if int(round(time.time())) > timeout_time:
                log("FATAL: Timed out waiting for "+ num_edge_nodes +" edge nodes to be registered. Current registered hosts: "+ edge_node_hosts)
                sys.exit()
            if len(edge_node_hosts) > 0:
                log("Completed edge node hosts: "+edge_node_hosts)
            time.sleep(3) 


    # Name: install_component_on_hosts
    # Install the specied host component on the specified hosts  
    # Parameters (in order):
    #   1: ambari_user
    #   2: ambari_password
    #   3: ambari_cluster_name
    #   4: component_name
    #   5: hosts (array of hostnames)
    def install_component_on_hosts(ambari_user, ambari_password, ambari_cluster_name, component_name, *hosts):
        client = Ambari('headnodehost', 8080, ambari_user, ambari_password)
        for host in hosts:
            log("Installing "+ component_name + " component on host: "+host)
            client.clusters(ambari_cluster_name).hosts(host).host_components(component_name).install().wait()


    # Name: deploy_ambari_service
    # Installs all host components for the specified service  
    # Parameters (in order):
    #   1: ambari_user
    #   2: ambari_password
    #   3: ambari_cluster_name
    #   4: service_name
    def deploy_ambari_service(ambari_user, ambari_password, ambari_cluster_name, service_name):
        log("Deploying all components for service: " + service_name)
        client = Ambari('headnodehost', 8080, ambari_user, ambari_password)
        response = client.clusters(ambari_cluster_name).services(service_name)
        #TODO: Haven't finished this function


        # Name: restart_ams_if_necessary
    # Restarts the Ambari Metrics Service collector service if the service is running on this host. This is required to make any new metrics registered in the whitelist file effective.
    # Parameters (in order)
    #   1: ambari_user 
    #   2: ambari_password 
    #   3: ambari_cluster 
    def restart_ams_if_necessary(ambari_user, ambari_password, ambari_cluster_name):
        ams_collector_host = next(iter(client.clusters(ambari_cluster_name).services('AMBARI_METRICS').components('METRICS_COLLECTOR').host_components))
        ams_host_name = ams_collector_host.host_name
        #TODO: Figure out a way to get FQDN of the host
        host_fqdn = socket.getfqdn()
        host_fqdn_parsed = str.split(host_fqdn,'.')
        if len(host_fqdn_parsed)==1:
            ams_host_name = str.split(ams_host_name.encode('ascii','ignore'), '.')[0]
        if host_fqdn == ams_host_name:
            log("Restarting AMS to make new whitelist metrics effective")
            #TODO: Check & Test if this restarts AMS correctly
            ams_collector_host.restart().wait()



    
    # Name: log
    # Echo supplied message with timestamp to stdout
    # Parameters:
    #   1: message
    def log(message):
        print "date ",int(round(time.time())),message