#!/usr/bin/env python
from resource_management import *
import os, glob

# server configurations
config = Script.get_config()

zk_quorum = config['configurations']['hbase-site']['hbase.zookeeper.quorum']
zk_basedir = config['configurations']['hbase-site']['zookeeper.znode.parent']
titandb_site = config['configurations']['titandb-site']
tdb_port = titandb_site['server.port']
tdb_hosts = config['clusterHostInfo']['titandb_server_hosts']
cert_name = os.path.splitext(os.path.basename(glob.glob("/var/lib/waagent/*.prv")[0]))[0]
ams_collector_host = config['clusterHostInfo']['metrics_collector_hosts'][0]

