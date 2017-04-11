#!/usr/bin/python

import os, os.path, sys, imp, tempfile, shutil, tarfile, stat, argparse, itertools, logging, json, shutil
import requests, time
import pip
from multiprocessing import Process, current_process
from sys import platform as _platform
from purl import URL
from ambariclient.client import Ambari
from ambariclient.exceptions import ServerError, NotFound, Conflict
import shared_ambari_installation as shared_lib

log = logging.getLogger()

if _platform == 'linux' or _platform == 'linux2':
    sys.path.append('/usr/lib/ambari-server/lib')
    import resource_management as rm
else:
    sys.path.append('./external')
    import win_resource_management as rm

def initial_part(service_config, cluster, topology_info, num_edge_nodes, edge_node_tag, edge_dns_suffix, extra_config, template_base_uri, data_service, not_detached, logfile, verbosity):
    try:
        stack_service_base_path = data_service.get_stack_service_base_dir(cluster.stack.stack_name, cluster.stack.stack_version)
        log.debug('Stack installation dir: %s', stack_service_base_path)
        # Get the service tar ball
        log.debug('Downloading service package from: %s', service_config['package'])
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
        with rm.Environment():
            # We need all the Ambari agents to automatically pickup this new service
            ambari_conf_file = data_service.get_ambari_properties_location()
            log.debug('Modifying ambari properties file: %s. Set agent.auto.cache.update=true', ambari_conf_file)
            rm.ModifyPropertiesFile(ambari_conf_file, 
                                    properties = {'agent.auto.cache.update': 'true'})
            # If the service has a WebUX (exposed via edge node endpoint), then create the jar file that exposes this capability via an IFrame viewer
            # TODO: Add support for richer, separate UX
            if 'iframeViewer' in service_config and service_config['iframeViewer']:
                if edge_dns_suffix and template_base_uri:
                    try:
                        edge_dns_name = '{0}-{1}.apps.azurehdinsight.net'.format(cluster.cluster_name, edge_dns_suffix)
                        view_jarname = shared_lib.create_iframe_viewer(service_config['serviceName'], service_config['displayName'], edge_dns_name, template_base_uri, data_service)
                        if view_jarname:
                            views_dir = os.path.join(data_service.get_ambari_resources_base_dir(), 'views')
                            if not os.access(views_dir, os.F_OK):
                                os.makedirs(views_dir)
                            dir, fname = os.path.split(view_jarname)
                            view_fullname = os.path.join(views_dir, fname)
                            log.debug('Moving dynamically constructed viewer jar file from %s to %s', view_jarname, view_fullname)
                            shutil.copy(view_jarname, view_fullname)
                    except:
                        # We can tolerate failure here, just log the warning & move on
                        log.warn('Failed to create IFrame View for service. The service UX will not be available via Ambari Views. Details: ', exc_info=True)
                else:
                    log.warn('Not installing IFrame view for service as required arguments --edge-dns-suffix and --template-base-uri were not specified')

        log.info('Starting detached installation component. Will wait for cluster installation to complete prior to rebooting Ambari')
        if not_detached:
            detached_part(service_config, cluster, topology_info, num_edge_nodes, edge_node_tag, extra_config, data_service, logfile, verbosity)
        else:
            # Launch the detached script that must wait for all Ambari installations (including edge nodes) to complete
            # before proceeding with the complete service installation
            detached = Process(target=detached_part, args=(service_config, cluster, topology_info, num_edge_nodes, edge_node_tag, extra_config, data_service, logfile, verbosity, ))
            detached.daemon=True
            detached.start()
            # Completely detach the child process from this one - an exit handler terminates & waits
            # for the child process to close before exiting itself.
            current_process()._children.clear()
        return True
    except:
        log.fatal('FATAL: Failure during initial installation part. Details:', exc_info=True)
        return False

def detached_part(service_config, cluster, topology_info, num_edge_nodes, edge_node_tag, extra_config, data_service, logfile, verbosity):
    try:
        shared_lib.configure_loggers(logfile, verbosity)
        service_display_name = service_config['displayName'] if service_config['displayName'] else service_config['serviceName']
        log.info('Running detached installation component for service: %s', service_display_name)
        # Determine if AMS collector is running on this node (not necessarily the active headnode)
        if service_config['metrics']:
            log.info('Updating AMS metrics whitelist and restarting AMS collector to make effective.')
            service_dir = os.path.join(data_service.get_stack_service_base_dir(cluster.stack.stack_name, cluster.stack.stack_version), service_config['serviceName'])
            shared_lib.update_ams_whitelist(service_dir, data_service)
            shared_lib.restart_ams_if_necessary(cluster, data_service)
        # We only need the service registration to proceed once - do it on the active headnode
        if shared_lib.is_active_headnode(data_service):
            log.info('Performing full installation on active head node')
            # We defer the required reboot of Ambari - to make the service effective, until after the entire cluster has been setup
            if num_edge_nodes:
                edge_node_hosts = shared_lib.wait_for_edge_node_scripts(cluster, num_edge_nodes, edge_node_tag, data_service)
                if not edge_node_hosts:
                    return False
            else:
                if not shared_lib.wait_for_cluster_installation(cluster, data_service):
                    return False
                edge_node_hosts = set()
            # Make sure there are no lingering requests
            if not shared_lib.wait_for_requests_to_complete(cluster, data_service):
                return False
            # HDI provisioning is complete - we can restart Ambari now
            shared_lib.make_ambari_service_effective(service_display_name, data_service)

            # Create service & components
            log.info('Registering %s service with Ambari', service_display_name)
            service = cluster.services(service_config['serviceName'])
            try:
                # If we get a 404 exception here, the service has not been installed
                state = service.state
                log.info('Service: %s already exists. Not making any changes', service.service_name)
            except:
                # AmbariClient bug - if an exception is thrown during inflate(), then the _is_inflating property is left True
                service._is_inflating = False
                service.create(service_name=service_config['serviceName'])
                for component in service_config['components']:
                    log.debug('Adding service component: %s', component)
                    # python-ambariclient is a bit buggy around ServiceComponent creation
                    newComponent = service.components(component)
                    newComponent.load(newComponent.client.post(newComponent.url))

            # Create our initial configuration & make it the desired config (if a separate one hasn't already been defined)
            config_tag='INITIAL'
            cluster.fields += ('desired_config',)
            for config, component_config in service_config['configurations'].iteritems():
                # Ignore any failures here (normally due to configuration already existing)
                try:
                    # Create the configuration & make it the desired config in 1 call
                    # Merge the static config from the file with any specified at runtime
                    props = component_config['properties'];
                    if extra_config:
                        # Dynamic config can be specified on a per-configuration or all basis
                        if config in extra_config:
                            props.update(extra_config[config])
                        else:
                            props.update(extra_config)
                    desired_config={'type':config, 'tag':config_tag, 'properties': props}
                    cluster.update(Clusters={'desired_config': desired_config})
                except ServerError as ex:
                    # Just swallow the exception if the configuration already exists
                    log.debug('Configuration update call failed. Details: %d:%s', ex.code, ex.details)
                    # AmbariClient bug - if an exception is thrown during inflate(), then the _is_inflating property is left True
                    cluster._is_inflating = False
                    # If the cluster doesn't have a desired_config, make INITIAL that guy
                    if not config in cluster.desired_configs:
                        cluster.update(Clusters={'desired_config': {'type':config, 'tag':config_tag}})

            # Install components to the various hosts. Which hosts get what components depends on:
            #   a) the component's topology
            #   b) the specified topology of the 'main' component (if any)
            primary_component = None
            primary_component_host = None
            for component_name, component in service_config['components'].iteritems():
                component_topologies = []
                # There's multiple ways that component topologies are specified:
                #   1. The --component-topologies argument contained this component & we use the specified topologies
                #   2. The --topologies argument specifies topology(ies) that apply to components with "canOverrideTopology": true in configuration
                #   3. The configuration specifies static topologies for the component via the "topology" attribute
                if topology_info is not None and component_name in topology_info:
                    component_topologies = topology_info[component_name]
                elif topology_info is not None and '*' in topology_info and 'canOverrideTopology' in component:
                    # This component can be have it's topology overridden by runtime args
                    component_topologies = topology_info['*']
                elif 'topology' in component:
                    component_topologies = component['topology']
                else:
                    component_topologies = ()
                # Components can be conditionally installed
                # TODO: Make this a more structured mechanism rather than dynamically evaluating arbitrary code
                installComponent = True
                if 'installIf' in component:
                    try:
                        installComponent = eval(component['installIf'])
                    except SyntaxError:
                        log.warn('Failed to evaluate installation criteria for component: %s. The component will NOT be installed. Details: ', component_name, exc_info=True)
                        installComponent = False
                if installComponent:
                    component_host_names = set()
                    log.debug('For component: %s using topologies: %s', component_name, component_topologies)
                    for topology in component_topologies:
                        # If we get an error looking for each service's hosts, then default to edge node - this may leave the service in a broken state, but at least
                        # it will be installed and the user can manually adjust the hosts that each component is deployed to.
                        try:
                            if topology == 'region':
                                # All HBASE region services - get this list from Ambari
                                component_host_names.update([host_component.host_name for host_component in cluster.services('HBASE').components('HBASE_REGIONSERVER').host_components])
                            elif topology == 'edge':
                                # Edge nodes
                                component_host_names.update(edge_node_hosts)
                            elif topology == 'head':
                                # Namenodes
                                component_host_names.update([host_component.host_name for host_component in cluster.services('HDFS').components('NAMENODE').host_components])
                            elif topology == 'worker':
                                # Worker nodes
                                component_host_names.update([host_component.host_name for host_component in cluster.services('HDFS').components('DATANODE').host_components])
                        except NotFound as ex:
                            log.warn('Failed to retrieve list of hosts to deploy component: %s - defaulting to edge node. Details: %s', ex.details)
                            component_host_names.update(edge_node_hosts)
                    log.debug('For component: %s deploying to hosts: %s', component_name, component_host_names)
                    if 'startPrimary' in component and component['startPrimary'] and len(component_host_names):
                        primary_component = service.components(component_name)
                        primary_component_host = iter(component_host_names).next()
                        log.debug('Pre-starting component: %s on host: %s', component_name, primary_component_host)
                    # Install the component with Ambari
                    if len(component_host_names) > 0:
                        for host in [host for host in cluster.hosts(list(component_host_names))]:
                            try:
                                log.info('Installing %s component on host: %s', component_name, host.host_name)
                                host.components(component_name).create()
                            except Conflict:
                                log.info('Host component %s on host: %s already exists.', component_name, host.host_name)
                        time.sleep(data_service.get_delay_base_unit())
                    else:
                        log.warn('Component: %s using topology: %s did not have any hosts to install on. If this is not correct, the component can be manually deployed to specific hosts', component_name, component_topologies)
                else:
                    log.info('Skipping installation of component: %s. The configured criteria was not met.', component_name)

            # Deploy the service components to each host
            log.info('Deploying all service components to assigned hosts')
            service.update(RequestInfo={'context': 'Install {0} service components'.format(service_display_name)}, Body={'ServiceInfo': {'state': 'INSTALLED'}}).wait()

            # Some services require a single instance of their main component to be started first (avoids race conditions with keyspace creation, etc.)
            if primary_component and primary_component_host:
                log.info('Starting primary instance of service for artifact creation')
                cluster.hosts(primary_component_host).components(primary_component.component_name).start().wait()
                time.sleep(data_service.get_delay_base_unit() * 2)

            # finally, start the service
            log.info('Starting the %s service on all hosts', service_display_name)
            service.update(RequestInfo={'context': 'Start {0} service'.format(service_display_name)}, Body={'ServiceInfo': {'state': 'STARTED'}}).wait()
        else:
            # Restart Ambari to cause our new service artifacts to be registered
            shared_lib.make_ambari_service_effective(service_display_name, data_service)
        log.info('Completed installation for service: %s successfully. The service is now running all components.', service_display_name)
        return True

    except:
        log.fatal('FATAL: Failure during detached installation part. Details:', exc_info=True)
        return False

if __name__ == '__main__':
    argsparser = argparse.ArgumentParser()
    argsparser.add_argument('-c', '--config', required=True, help='URI pointing to JSON configuration file')
    argsparser.add_argument('-u', '--username', required=True, help='Ambari username')
    argsparser.add_argument('-p', '--password', required=True, help='Ambari password')
    topology_group = argsparser.add_mutually_exclusive_group()
    topology_group.add_argument('-t', '--topology', action='append', nargs='*', choices=['edge', 'region', 'worker', 'head'], 
        help=('Specify the deployment topology for this application. '
                'This value must be a subset of the available_topologies config setting. '
                'Combine multiple topologies by specifying this argument multiple times.'))
    topology_group.add_argument('--component-topologies', help='Specify component topology information as a JSON value in the form; {"component_name":["topology",...],...}')
    argsparser.add_argument('-e', '--num-edge-nodes', default=0, type=int, help='The number of edge nodes to deploy components onto')
    argsparser.add_argument('-n', '--edge-node-tag', default='edgenode-signature-tag', help='The string that will appear in the installation log file for all edge nodes.')
    argsparser.add_argument('-s', '--edge-dns-suffix', default='', help='DNS suffix applied to edge node URL where service endpoint will be exposed. In the form; "https://{cluster_name}-{edge-dns-suffix}.apps.azurehdinsight.net"')
    argsparser.add_argument('-x', '--extra-config', default='', help='Extra configuration information that will be merged with pre-configured configuration. This value should be in the form of a JSON object.')
    argsparser.add_argument('-z', '--template-base-uri', default='', help='Base uri pointing to a location where templates for this installation can be installed.')
    argsparser.add_argument('-a', '--ambari-host', default='http://headnodehost:8080', help='Base URI for Ambari api')
    argsparser.add_argument('--not-detached', action='store_true', help='DEBUG ONLY - do not detach second part of script')
    argsparser.add_argument('-l', '--logfile', default=None, help='Log file location')
    argsparser.add_argument('-v', '--verbosity', default='INFO', choices=['DEBUG', 'INFO', 'WARNING', 'ERROR'], help='Set logging verbosity level')
    argsparser.add_argument('-m', '--mock-service', default=None, help='Supply the class name of the service to mock data services')
    args = argsparser.parse_args()

    shared_lib.configure_loggers(args.logfile, args.verbosity)
    log.info('Starting install of Ambari service')
    try:
        config_request = requests.get(args.config)
        config_request.raise_for_status()
        service_config = config_request.json()
        log.debug('Service config: %s', service_config)
    except:
        log.error("Invalid configuration URI", exc_info=True)
        sys.exit(2)

    # Do some sanity checks on the config
    requiredAttribs = ['serviceName', 'package', 'components', 'configurations']
    for attrib in requiredAttribs:
        if not attrib in service_config:
            log.error("Invalid configuration. Missing required attribute '%s'", attrib)
            sys.exit(3)

    log.info('Installing service: %s on ambari host: %s', service_config['serviceName'], args.ambari_host)
    ambari_host_uri = URL(args.ambari_host)
    ambari_client = Ambari(ambari_host_uri.host(), port=ambari_host_uri.port(), protocol=ambari_host_uri.scheme(), username=args.username, password=args.password, identifier='hdiapps')
    # If this is being invoked from outside the cluster, we must fixup the href references contained within the responses
    ambari_client.client.request_params['hooks'] = dict(response=shared_lib.Fixup(ambari_host_uri).fixup)
    # Assume we only have 1 cluster managed by this Ambari installation 
    cluster = ambari_client.clusters.next()
    log.debug('Cluster: %s, href: %s', cluster.cluster_name, cluster._href)

    # Pull in any extra dynamic configuration
    if args.extra_config:
        try:
            extra_config = json.loads(args.extra_config)
            log.debug('Applying dynamic service configuration specified on command-line: %s', extra_config)
        except:
            log.warning('Extra configuration specified by the -x argument could not be parsed as JSON. The value was \'%s\'. Details: ', args.extra_config, exc_info=True)
            extra_config = {}    
    else:
        extra_config = {}

    topology_info = None
    if args.component_topologies is not None:
        try:
            topology_info = json.loads(args.component_topologies)
        except:
            log.warning('Failed to parse specified topology JSON value: \'%s\'', args.component_topologies, exc_info=True)
            sys.exit(4)
    elif args.topology is not None:
        # ArgumentParser yields this arg as a list of lists. Need to flatten before manipulation
        topology_info = {'*': list(itertools.chain.from_iterable(args.topology))}

    # Instantiate our Mock service is specified
    mock_service = None
    if args.mock_service:
        module = shared_lib
        module_name, delim, class_name = args.mock_service.rpartition('.')
        if module_name:
            module = __import__(module_name)
        mock_service = getattr(module, class_name)()
    else:
        mock_service = shared_lib.MockableService()

    # Kick off the initial processing, which will in turn launch a detached script to complete the installation process
    if not initial_part(service_config, cluster, topology_info, args.num_edge_nodes, args.edge_node_tag, args.edge_dns_suffix, extra_config, args.template_base_uri, mock_service, args.not_detached, args.logfile, args.verbosity):
        sys.exit(4)
