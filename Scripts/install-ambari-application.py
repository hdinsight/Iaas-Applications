#!/usr/bin/python

import os, os.path, sys, imp, tempfile, shutil, tarfile, stat, argparse
import requests
import pip
from multiprocessing import Process, current_process

sys.path.append('/usr/lib/ambari-server/lib')
from resource_management import *

# Dynamically load some modules
pip.main(['install', 'purl'])
from purl import URL
pip.main(['install', 'python-ambariclient'])
from ambariclient.client import Ambari

def initial_part(service_config, ambari_client, selected_topology, num_edge_nodes, scripts_base_uri):
    # Download & load the shared module
    scripts_base_url = URL(scripts_base_uri)
    tempdir = tempfile.gettempdir()
    sys.path.append(tempdir)
'''    shared_module_pathspec = os.path.join(tempdir, 'shared-ambari-installation.py')
    req = requests.get(scripts_base_url.add_path_segment('shared-ambari-installation.py').as_string(), stream=True)
    with open(shared_module_pathspec, 'wb') as fd:
        shutil.copyfileobj(req.raw, fd)
    import shared-ambari-installation
'''
    # Assume we only have 1 cluster managed by this Ambari installation
    cluster = ambari_client.clusters.next()

    stack_service_base_path = '/var/lib/ambari-server/resources/stacks/{0}/{1}/services'.format(cluster.stack.stack_name, cluster.stack.stack_version)
    # Get the service tar ball
    req = requests.get(service_config['package'], stream=True)
    with tempfile.NamedTemporaryFile(prefix="service-tarball-", suffix=".tar.gz", delete=False) as fd:
        shutil.copyfileobj(req.raw, fd)
        fd.seek(0)
        tar = tarfile.open(fileobj=fd)
        tar.extractall(stack_service_base_path)
    # If we build the tarball on Windows, the wrong permissions are set
    for root, dirs, files in os.walk(os.path.join(stack_service_base_path, service_config['serviceName'])):
        os.chmod(root, 0644)
        for dir in dirs:
            os.chmod(os.path.join(root, dir), 0644)
        for file in files:
            os.chmod(os.path.join(root, file), 0644)

    # Ambari resource_manager requires an Environment instance to be effective
    with Environment() as env:
        # We need all the Ambari agents to automatically pickup this new service
        ModifyPropertiesFile('/etc/ambari-server/conf/ambari.properties', 
                            properties = {'agent.auto.cache.update': 'true'})

        # Launch the detached script that must wait for all Ambari installations (including edge nodes) to complete
        # before proceeding with the complete service installation
        detached = Process(target=detached_part, args=(service_config, ambari_client, cluster, ))
        detached.daemon=True
        detached.start()
        # Completely detach the child process from this one - an exit handler terminates & waits
        # for the child process to close before exiting itself.
        current_process()._children.clear()

def detached_part(service_config, ambari_client, cluster):
    import time
    time.sleep(10)
    print cluster.cluster_name
    print service_config
    time.sleep(10)
    print 'End'

if __name__ == '__main__':
    try:
        argsparser = argparse.ArgumentParser()
        argsparser.add_argument('-c', '--config', required=True, help='URI pointing to JSON configuration file')
        argsparser.add_argument('-u', '--userName', required=True, help='Ambari username')
        argsparser.add_argument('-p', '--password', required=True, help='Ambari password')
        argsparser.add_argument('-t', '--topology', required=True, action='append', nargs='*',choices=['edge', 'region', 'workers', 'head'], 
            help=('Specify the deployment topology for this application. '
                  'This must be a subset of the available_topologies config setting. '
                  'Combine multiple topologies by specifying this argument multiple times.'))
        argsparser.add_argument('-e', '--num-edge-nodes', default=0, type=int, help='The number of edge nodes to deploy components onto')
        argsparser.add_argument('-s', '--scripts-base-uri', default='https://github.com/jamesbak/Iaas-Applications/raw/titandb/Scripts/',
            help='The location of all other scripts associated with this deployment.')
        args = argsparser.parse_args()
        
        args = iter(sys.argv)
        next(args)

        config_file_uri = next(args)
        ambari_user = next(args)
        ambari_password = next(args)
        selected_topology = next(args, 0)
        num_edge_nodes = next(args, 0)
        scripts_base_uri = next(args, 'https://github.com/jamesbak/Iaas-Applications/raw/titandb/Scripts/')
    except:
        print "Usage: install-ambari-application.py {config-file-uri} {ambari-username} {ambari-password} [topology] [num-edge-nodes]"
        print "Where:"
        print "     config-file-uri: URI pointing to static JSON configuration file"
        print "     ambari-username, ambari-password:    username & password used to make Ambari calls"
        print "     topology (optional): The required installation topology (may be combined). If omitted, value is read from static configuration:"
        print "         1: edge nodes"
        print "         2: region nodes"
        print "         4: all worker nodes"
        print "         8: head nodes"
        print "     num-edge-nodes (optional): The number of edge nodes to install on. Only applicable if topology includes edge nodes."
        sys.exit(1)

    try:
        config_request = requests.get(config_file_uri)
        config_request.raise_for_status()
        service_config = config_request.json()
    except:
        print "Invalid configuration URI"
        print "Details: ", sys.exc_info()
        sys.exit(2)

    # Do some sanity checks on the config
    if not service_config.has_key('package'):
        print "Invalid configuration. Missing required attribute 'package'"
        sys.exit(3)
    elif not service_config.has_key('components'):
        print "Invalid configuration. Missing required attribute 'components'"
        sys.exit(3)

    ambari_client = Ambari('headnodehost', 8080, ambari_user, ambari_password, 'hdiapps')
    # Kick off the initial processing, which will in turn launch a detached script to complete the installation process
    initial_part(service_config, ambari_client, selected_topology, num_edge_nodes, scripts_base_uri)
