#!/usr/bin/python

import os, os.path, sys, imp, datetime, time, logging, socket, json, tempfile, itertools, zipfile
import requests
from purl import URL
import pip
from ambariclient.client import Ambari
from sys import platform as _platform

log = logging.getLogger(__name__)

if _platform == 'linux' or _platform == 'linux2':
    sys.path.append('/usr/lib/ambari-server/lib')
    import resource_management as rm
else:
    sys.path.append('./external')
    import win_resource_management as rm

def configure_loggers(logfile, verbosity):
    # We need 2 handlers so that we can split stdout & stderr + a filter to ensure warning+error messages don't go to stdout
    # pip installs its own loggers - blow these away
    # Optionally add a file-based log destination
    rootLogger = logging.getLogger()
    for handler in rootLogger.handlers[:]:
        rootLogger.removeHandler(handler)
    rootLogger.setLevel(logging.NOTSET)
    logging._defaultFormatter = logging.Formatter('%(asctime)s - %(process)d - %(name)s - %(levelname)s - %(message)s')
    stdout_handler = logging.StreamHandler(sys.stdout)
    stdout_handler.setLevel(verbosity)
    stdout_handler.addFilter(pip.utils.logging.MaxLevelFilter(logging.WARNING))
    stderr_handler = logging.StreamHandler(sys.stderr)
    stderr_handler.setLevel(logging.WARNING)
    rootLogger.addHandler(stdout_handler)
    rootLogger.addHandler(stderr_handler)
    if logfile:
        file_handler = logging.FileHandler(logfile)
        file_handler.setLevel(verbosity)
        rootLogger.addHandler(file_handler)

def is_active_headnode(data_service):
    """Name: is_active_headnode
    Determines if the current node is the active headnode by comparing IP address with 'headnodehost'
    """
    try:
        return data_service.is_active_headnode()
    except socket.error:
        log.debug('Failed to resolve host headnodehost or own address. Details: ', exc_info=True)
        # Just eat the exception assuming we can't resolve headnodehost
        return False

def download_template(source_uri_base, source_file, dest_dir, dest_filename, is_template, *args, **kwargs):
    dest_filename = os.path.join(dest_dir, dest_filename if dest_filename else source_file)
    with open(dest_filename, 'w') as fp:
        response = requests.get(URL(source_uri_base).add_path_segment(source_file).as_string())
        response.raise_for_status()
        if is_template:
            content = rm.InlineTemplate(response.text, **kwargs).get_content()
        else:
            content = response.text
        fp.write(content)
        log.debug('Writing to %s. Content: %s', dest_filename, content)
    return dest_filename

def create_iframe_viewer(service_name, display_name, edge_dns_name, template_base_uri, data_service):
    """Name: create_iframe_viewer
    Generates a simple Web UX wrapper that can be installed as an Ambari View by wrapping the service's built-in
    web UX in an IFrame.
    Note that this function should be called while an Ambari.Environment is active. Eg:
        with Environment():
            ...
            shared.create_iframe_viewer(...)
    """
    try:
        view_name = service_name.lower() + '-view'
        view_label = (display_name if display_name else service_name) + ' View'
        view_dir = tempfile.mkdtemp('view', service_name)
        view_jarfilename = view_name + '.jar'
        full_jarspec = os.path.join(view_dir, view_jarfilename)
        jar_dir = os.path.join(view_dir, 'jar')
        meta_inf_dir = os.path.join(jar_dir, 'META-INF')
        log.debug('Building IFrame View at location: %s to point to edge node at address: %s', full_jarspec, edge_dns_name)
        os.makedirs(meta_inf_dir)
        # Construct the variables that will be available for template substitution
        template_vars = {
            'edge_uri': 'https://' + edge_dns_name,
            'view_name': view_name.upper(),
            'view_label': view_label
        }
        # The order the we add things to the zip/jar is significant - manifest information must be first
        with zipfile.ZipFile(full_jarspec, 'w', zipfile.ZIP_DEFLATED) as zip:
            zip.write(download_template(template_base_uri, 'MANIFEST.MF', meta_inf_dir, None, False), 'META-INF/MANIFEST.MF')
            zip.write(download_template(template_base_uri, 'index.html.j2', jar_dir, 'index.html', True, **template_vars), 'index.html')
            zip.write(download_template(template_base_uri, 'view.xml.j2', jar_dir, 'view.xml', True, **template_vars), 'view.xml')
        return full_jarspec
    except:
        log.warn('Failed to create IFrame view jar file. Details: ', exc_info=True)
        return ''

def update_ams_whitelist(service_base_dir, data_service):
    """Name: update_ams_whitelist
    Extracts all of the metrics names from the metrics.json file in the specified service stack directory
    and adds them to the ams whitelist file. The AMS collector must be restarted to make the whitelist
    changes effective. See restart_ams_if_necessary() for details.
    """
    try:
        # TODO: See if there's a better way to determine this location
        whitelist_filename = os.path.join(data_service.get_ams_collector_config(), 'whitelistedmetrics.txt')
        metrics_filename = os.path.join(service_base_dir, 'metrics.json')
        log.debug('Adding metrics from: %s to whitelist file: %s', metrics_filename, whitelist_filename)
        whitelist_metrics = set()
        with open(metrics_filename) as metrics_fp:
            metrics = json.load(metrics_fp)
            for component_name, component in metrics.iteritems():
                # The AMS metrics.json file needs a couple of entries for each metric - we only need the first
                whitelist_metrics.update([metric_name for metric_name in component['Component'][0]['metrics']['default']])
        with open(whitelist_filename, 'a+') as whitelist_fp:
            whitelist_metrics.update(whitelist_fp.read().splitlines())
            whitelist_fp.seek(0, os.SEEK_SET)
            whitelist_fp.truncate()
            whitelist_fp.writelines(sorted([(metric + '\n') for metric in whitelist_metrics]))

    except:
        log.warn('Unable to update AMS metrics whitelist file. Metrics will not be available for this service. Details: ', exc_info=True)

def restart_ams_if_necessary(ambari_cluster, data_service):
    """Name: restart_ams_if_necessary
    Restarts the Ambari Metrics Service collector service if the service is running on this host. This is required to make any new metrics registered in the whitelist file effective.
    """
    #Ambari holds the fqdn of each host
    ams_collector_host = ambari_cluster.services('AMBARI_METRICS').components('METRICS_COLLECTOR').host_components.next().host_name
    this_host = socket.getaddrinfo(socket.gethostname(), 0, 0, 0, 0, socket.AI_CANONNAME)[0][3]
    if data_service.is_ams_collector_host(ams_collector_host, this_host):
        try:
            log.info("Restarting AMS to make new whitelist metrics effective")
            with rm.Environment():
                rm.Execute([data_service.get_ams_collector_exe(), '--config', data_service.get_ams_collector_config(), 'restart'], user='ams', logoutput=True)
        except rm.Fail as ex:
            log.warning('Failed to successfully restart AMS metrics collector. Details: %s', ex.message)

def wait_for_cluster_installation(ambari_cluster, data_service):

    """Name: wait_for_cluster_installation
    Wait for cluster installation to complete by waiting for the 'Auto Start Host Comonents' task to complete.
    Note that this should only be used when 0 edge nodes are due to be installed.
    """
    # We defer the required reboot of Ambari - to make the service effective, until after the entire cluster
    # have been fully deployed. This is determined by waiting for a task 'Auto Start Host Components' to complete.
    log.info('Waiting for completion of cluster installation')
    # Ambari time is ms
    start_time = datetime.datetime.utcnow()
    # Wait around for 30 mins
    timeout_time = start_time + datetime.timedelta(seconds=data_service.get_installation_timeout())
    while datetime.datetime.utcnow() < timeout_time:
        # Make this call mockable
        requests = list(data_service.get_cluster_requests(ambari_cluster, request_context='Auto Start Host Components', request_status='COMPLETED'))
        if len(requests) > 0:
            for request in requests:
                request_start_time = datetime.datetime.utcfromtimestamp(request.start_time / 1000)
                log.debug('Seen request: %d, Start time: %s, Status: %s:%s', request.id, request_start_time, request.status, request.request_status)
            log.info('Detected that "Auto Start Host Components" request has completed. Therefore, the cluster has been fully provisioned')
            return True
        time.sleep(data_service.get_delay_base_unit())
    log.fatal('FATAL: Timed out waiting for Ambari cluster installation to complete')
    return False

def wait_for_edge_node_scripts(ambari_cluster, num_edge_nodes, edgenode_script_tag, data_service):
    """Name: wait_for_edge_node_scripts
    Wait for all edge node placeholder scripts to be executed. This is detected by polling Ambari requests, looking for the 
    specified signature tag to be present in the output of the task. If this is not detected prior to timeout, the script is 
    fatally terminated.
    Outputs: 
      edge_node_hosts (array of edge node hostnames)
    """
    # We defer the required reboot of Ambari - to make the service effective, until after the entire cluster,
    # including edge nodes, have been fully deployed. 
    # To detect when the edge node(s) have been fully deployed, we watch for a request to 'run_customscriptaction' which
    # is the script action running on the edge nodes
    log.info("Waiting for the registration of %d edge nodes", num_edge_nodes)
    # Wait around for 30 mins
    timeout_time = datetime.datetime.utcnow() + datetime.timedelta(seconds=data_service.get_installation_timeout())
    edge_node_hosts = set()
    while len(edge_node_hosts) < num_edge_nodes:
        edge_node_hosts = set()
        # Make this call mockable
        custom_action_requests = data_service.get_cluster_requests(ambari_cluster, request_context='run_customscriptaction', request_status='COMPLETED')
        for request in custom_action_requests:
            for task in request.tasks:
                if task.stdout.find(edgenode_script_tag) != -1:
                    task_hosts = set(request.resource_filters[0]['hosts'])
                    log.info('Found edge node custom action script run on these hosts: %s', task_hosts)
                    edge_node_hosts |= task_hosts

        if datetime.datetime.utcnow() > timeout_time:
            log.fatal('FATAL: Timed out waiting for %d edge nodes to be registered. Current registered hosts: %s', num_edge_nodes, edge_node_hosts)
            return False
        time.sleep(data_service.get_delay_base_unit())
    return edge_node_hosts

def wait_for_requests_to_complete(ambari_cluster, data_service):
    """Name: wait_for_requests_to_complete
    Wait for any currently active requests to complete.
    """
    # We defer the required reboot of Ambari - to make the service effective, until after the entire cluster
    # have been fully deployed. This is determined by waiting for a task 'Auto Start Host Components' to complete.
    log.info('Waiting for completion of any outstanding requests')
    start_time = datetime.datetime.utcnow()
    # Wait around for 30 mins
    timeout_time = start_time + datetime.timedelta(seconds=data_service.get_installation_timeout())
    while datetime.datetime.utcnow() < timeout_time:
        # Make this call mockable
        requests = list(data_service.get_cluster_requests(ambari_cluster, request_status='IN_PROGRESS'))
        if len(requests) == 0:
            log.info('No active requests are running on cluster.')
            return True
        log.debug('Detected %d running requests on cluster. Pausing until they all complete.', len(requests))
        time.sleep(data_service.get_delay_base_unit())
    log.fatal('FATAL: Timed out waiting for Ambari cluster installation to complete')
    return False
    
def make_ambari_service_effective(service_name, data_service):
    """Name: make_ambari_service_effective
    Performs all operations necessary (ie. restart) to register new service with Ambari
    """
    log.info('Proceeding with registration & installation of %s service + components on head node', service_name)
    time.sleep(data_service.get_delay_base_unit() * 2)
    log.info('Restarting Ambari on head node to register %s service', service_name)
    with rm.Environment():
        rm.Execute(('ambari-server', 'refresh-stack-hash'))
        rm.Service('ambari-server', action='restart')
    # We have to wait for it to come back up properly 
    time.sleep(data_service.get_delay_base_unit() * 3)

class Fixup(object):
    def __init__(self, base_uri):
        self._base_uri = base_uri

    def fixup(self, r, *args, **kwargs):
        try:
            # Make sure the response is fully loaded before we try to touch the headers or json. None of the Ambari client responses
            # are streamed anyway.
            s = r.content
            if 'Content-Length' in r.headers and int(r.headers['Content-Length']):
                body = r.json()
                if self.do_fixup_recursive(body):
                    r._content = json.dumps(body)
                    return r
        except:
            log.debug('Exception fixing up ambari client response. Details: ', exc_info=True)

    def do_fixup_recursive(self, obj):
        retval = False
        if 'href' in obj:
            _href = URL(obj['href']).scheme(self._base_uri.scheme()).host(self._base_uri.host()).port(self._base_uri.port() if self._base_uri.port() else (443 if self._base_uri.scheme() == 'https' else 80))
            obj['href'] = str(_href)
            retval = True
        for key in obj:
            if isinstance(obj[key], list):
                for item in obj[key]:
                    retval |= self.do_fixup_recursive(item)
        return retval

class MockableService(object):
    def is_active_headnode(self):
        return socket.gethostbyname('headnodehost') == socket.gethostbyname(socket.gethostname())
        
    def is_ams_collector_host(self, ams_collector_host, this_host):
        return ams_collector_host == this_host

    def get_ambari_resources_base_dir(self):
        if _platform == 'linux' or _platform == 'linux2':
            return '/var/lib/ambari-server/resources'
        else:
            return os.path.join(tempfile.gettempdir(), 'ambari-resources')

    def get_stack_service_base_dir(self, stack_name, stack_version):
        return os.path.join(self.get_ambari_resources_base_dir(), 'stacks', stack_name, stack_version, 'services')

    def get_ambari_properties_location(self):
        base_dir = ''
        if _platform == 'linux' or _platform == 'linux2':
            base_dir = '/etc/ambari-server/conf'
        else:
            base_dir = '.\\conf'
        return os.path.join(base_dir, 'ambari.properties')

    def get_ams_collector_exe(self):
        # Linux-only implementation - MUST be mocked out on Windows
        return '/usr/sbin/ambari-metrics-collector'

    def get_ams_collector_config(self):
        if _platform == 'linux' or _platform == 'linux2':
            return '/etc/ambari-metrics-collector/conf/'
        else:
            return '.\\external\\conf'

    def get_cluster_requests(self, ambari_cluster, *args, **kwargs):
        requests = ambari_cluster.requests(*args, **kwargs)
        requests.refresh()
        requests._iter_marker = 0
        return requests

    def get_delay_base_unit(self):
        return 5

    def get_installation_timeout(self):
        # Default is 30mins to wait for installation completion
        return 30 * 60
        
