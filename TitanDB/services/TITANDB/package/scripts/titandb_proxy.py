#!/usr/bin/env python

import sys, os, pwd, signal, time, glob
from resource_management import *

class TitanDBProxy(Script):
  def install(self, env):
    # Install packages listed in metainfo.xml
    self.install_packages(env)
    Logger.info("TitanDBProxy - Nothing to install. All components installed by HDInsight.")

  def configure(self, env):
    import params
    env.set_params(params)

    Logger.info("TitanDBProxy - Starting configuration.")
    # The standard HDI installation leaves nginx.conf with invalid TLS certs (they use placeholders). We
    # need to replace the placeholder with real cert info (loaded via params)
    nginx_conf = '/etc/nginx/nginx.conf'
    cert_placeholder_replace = ('sed', '-i', 's|ssl_certificate /var/lib/waagent/.*.crt|ssl_certificate /var/lib/waagent/{0}.crt|'.format(params.cert_name), nginx_conf)
    Execute(cert_placeholder_replace)
    cert_placeholder_replace = ('sed', '-i', 's|ssl_certificate_key /var/lib/waagent/.*.prv|ssl_certificate_key /var/lib/waagent/{0}.prv|'.format(params.cert_name), nginx_conf)
    Execute(cert_placeholder_replace)
    File("/etc/nginx/sites-available/default",
         content = Template("nginx-sites-available-default.j2"))
    Logger.info("TitanDBProxy - Configuration completed.")

  def start(self, env):
    import params
    self.configure(env)

    Logger.info("TitanDBProxy - Starting service.")
    Execute('service nginx start')
    Logger.info("TitanDBProxy - Service is running.")

  def stop(self, env):
    Logger.info("TitanDBProxy - Stopping service.")
    Execute('service nginx stop')
    Logger.info("TitanDBProxy - Service is stopped.")

  def status(self, env):
    check_process_status('/var/run/nginx.pid')

if __name__ == "__main__":
  TitanDBProxy().execute()


