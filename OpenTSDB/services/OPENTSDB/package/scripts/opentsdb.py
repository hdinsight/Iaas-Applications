#!/usr/bin/env python

import sys, os, pwd, signal, time
from resource_management import *

class OpenTSDB(Script):
  def install(self, env):
    # Install packages listed in metainfo.xml
    self.install_packages(env)
    import params

    Logger.info("OpenTSDB - Starting installation.")
    Execute('wget https://github.com/OpenTSDB/opentsdb/releases/download/v{0}/opentsdb-{0}_all.deb -O /tmp/opentsdb_all.deb'.format(params.opentsdb_version))
    Execute('dpkg -i /tmp/opentsdb_all.deb')
    # Extend the OpenTSDB start script to include JAVA 8
    with open('/etc/init.d/opentsdb', 'r+') as f:
      new_contents =  re.sub(r'JDK_DIRS="(.*?)"', r'JDK_DIRS="\1 /usr/lib/jvm/java-8-openjdk-amd64"', f.read(), 0, re.DOTALL)
      f.seek(0)
      f.write(new_contents)
      f.truncate()
    # We also need jq for metrics transformation
    Package('jq')
    # Force to 1.5 (some of the package managers are a bit behind)
    Execute('wget https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64 -O /usr/bin/jq')

    if params.create_schema:
      Logger.info('Creating HBase tables. TSDB_TABLE: {0}, UID_TABLE: {1}'.format(params.opentsdb_site['tsd.storage.hbase.data_table'], params.opentsdb_site['tsd.storage.hbase.uid_table']))
      Execute('/usr/share/opentsdb/tools/create_table.sh', 
              environment={'HBASE_HOME': '/usr', 'COMPRESSION': 'SNAPPY', 'TSDB_TABLE': params.opentsdb_site['tsd.storage.hbase.data_table'], 'UID_TABLE': params.opentsdb_site['tsd.storage.hbase.uid_table'] }, 
              logoutput=True)
      Logger.info('HBase tables created')
      
    # Copy the metrics script to an executable location
    File('/etc/opentsdb/metrics_sink.sh',
         content=StaticFile('metrics_sink.sh'),
         mode=0755)
    Logger.info("OpenTSDB - Installation complete.")

  def configure(self, env):
    import params
    env.set_params(params)

    Logger.info("OpenTSDB - Starting configuration.")
    Logger.info(format("zk_quorum: {params.zk_quorum}, zk_basedir: {params.zk_basedir}"))
    opentsdb_config_file = '/etc/opentsdb/opentsdb.conf'
    tsd_server_config = self.mutable_config_dict(params.opentsdb_site)
    tsd_server_config['tsd.storage.hbase.zk_basedir'] = params.zk_basedir
    tsd_server_config['tsd.storage.hbase.zk_quorum'] = params.zk_quorum
    PropertiesFile(opentsdb_config_file,
                   properties = tsd_server_config,
                   mode = 0644)

    Logger.info("OpenTSDB - Configuration completed.")

  def start(self, env):
    import params
    self.configure(env)

    Logger.info("OpenTSDB - Starting service.")
    Execute('service opentsdb start')
    Logger.info("OpenTSDB - Service is running.")
    # Install metrics sink (cron job hitting the tsd's stats API)
    Logger.info("Installing CRON job to gather metrics")
    File("/etc/cron.d/optsdb-metrics",
         content = format("* * * * * root /etc/opentsdb/metrics_sink.sh {tsd_port} {ams_collector_host} >> /var/log/opentsdb/optsdb-metrics.log 2>&1\n"))
    Logger.info("CRON job registered to gather metrics")

  def stop(self, env):
    Logger.info("Stopping metrics CRON job")
    File("/etc/cron.d/optsdb-metrics",
         action = "delete")
    Logger.info("OpenTSDB - Stopping service.")
    Execute('service opentsdb stop')
    Logger.info("OpenTSDB - Service is stopped.")

  def status(self, env):
    check_process_status('/var/run/opentsdb.pid')

  def mutable_config_dict(self, immutable_config):
    mutable_config = {}
    for key, value in immutable_config.iteritems():
      mutable_config[key] = value
    return mutable_config


if __name__ == "__main__":
  OpenTSDB().execute()
