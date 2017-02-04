from ambariclient.client import Ambari
sys.path.append('/usr/lib/ambari-server/lib')
from resource_management import *
from shared-ambari-installation import *
import time, urllib, tarfile, os, sys, stat

class ambari-services:
    def create-ambari-services(user, password, cluster, active_headnode, num_edge_nodes, edgenode_script_tag, titan_listen_port, selected_topology):
        restart_ams_if_necessary(user, password, cluster)


