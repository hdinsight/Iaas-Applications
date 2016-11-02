#!/usr/bin/env python

import sys, os, pwd, signal, time
from resource_management import *

class TitanDB(Script):
  def install(self, env):
    # Install packages listed in metainfo.xml
    self.install_packages(env)
    import params

    Logger.info("TitanDB - Starting installation.")
    Execute('wget http://s3.thinkaurelius.com/downloads/titan/titan-1.0.0-hadoop1.zip -O /tmp/titan-1.0.0-hadoop1.zip')
    Execute('unzip -o /tmp/titan-1.0.0-hadoop1.zip -d /usr/share/')
    Directory('/var/run/titandb')
    File("/etc/systemd/system/titandb.service",
        content=StaticFile("titandb.service")
    )     
    Execute('systemctl daemon-reload')
    Execute('systemctl enable titandb.service')
    # We also need jq for metrics transformation
    Package('jq')
    # Download ElasticSearch
    es_package = 'elasticsearch-1.7.1.deb'
    Execute('wget https://download.elastic.co/elasticsearch/elasticsearch/{0} -O /tmp/{0}'.format(es_package))
    Execute('dpkg -i /tmp/{0}'.format(es_package))
    # Enable ES as a systemd service
    Execute('systemctl daemon-reload')
    Execute('systemctl enable elasticsearch.service')

    Logger.info("TitanDB - Installation complete.")

  def configure(self, env):
    import params
    env.set_params(params)

    Logger.info("TitanDB - Starting configuration.")

    Logger.info(format("zk_quorum: {params.zk_quorum}, zk_basedir: {params.zk_basedir}"))
    # Configure ElasticSearch first
    File("/etc/elasticsearch/elasticsearch.yml",
        content=StaticFile("elasticsearch.yml")
    )     
    # Titan has 2 config files - 1 for the graph itself & another for the server   
    titan_config = self.mutable_config_dict(params.titandb_site)
    titan_config['storage.hostname'] = params.zk_quorum
    titan_config['storage.hbase.ext.zookeeper.znode.parent'] = params.zk_basedir
    titan_config['gremlin.graph'] = "com.thinkaurelius.titan.core.TitanFactory"
    PropertiesFile('/usr/share/titan-1.0.0-hadoop1/conf/gremlin-server/titan-hbase-es-server.properties',
                   properties = titan_config,
                   mode = 0644)
    File("/usr/share/titan-1.0.0-hadoop1/conf/gremlin-server/gremlin-server.yaml",
        content=Template("gremlin-server.yaml.j2")
    )

    Logger.info("TitanDB - Configuration completed.")

  def start(self, env):
    import params
    self.configure(env)

    Logger.info("TitanDB - Starting service.")
    Execute('systemctl start elasticsearch.service')
    time.sleep(5)
    Execute('systemctl start titandb.service')
    Logger.info("TitanDB - Service is running.")

  def stop(self, env):
    Logger.info("TitanDB - Stopping service.")
    Execute('systemctl stop titandb.service')
    Execute('systemctl stop elasticsearch.service')
    Logger.info("TitanDB - Service is stopped.")

  def status(self, env):
    check_process_status('/var/run/titandb/titandb.pid')

  def mutable_config_dict(self, immutable_config):
    mutable_config = {}
    for key, value in immutable_config.iteritems():
      mutable_config[key] = value
    return mutable_config


if __name__ == "__main__":
  TitanDB().execute()
