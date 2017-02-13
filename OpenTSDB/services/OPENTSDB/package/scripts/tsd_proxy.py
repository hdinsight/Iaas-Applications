#!/usr/bin/env python

import sys, os, pwd, signal, time, glob
from resource_management import *

class TSDProxy(Script):
  def install(self, env):
    # Install packages listed in metainfo.xml
    self.install_packages(env)
    Logger.info("TSDProxy - Nothing to install. All components installed by HDInsight.")

  def configure(self, env):
    import params
    env.set_params(params)

    Logger.info("TSDProxy - Starting configuration.")
    # The standard HDI installation leaves nginx.conf with invalid TLS certs (they use placeholders). We
    # need to replace the placeholder with real cert info (loaded via params)
    cert_placeholder_replace = ('sed', '-i', 's|ssl_certificate /var/lib/waagent/.*.crt|ssl_certificate /var/lib/waagent/{0}.crt|'.format(params.cert_name), '/etc/nginx/nginx.conf')
    Execute(cert_placeholder_replace)
    cert_placeholder_replace = ('sed', '-i', 's|ssl_certificate_key /var/lib/waagent/.*.prv|ssl_certificate_key /var/lib/waagent/{0}.prv|'.format(params.cert_name), '/etc/nginx/nginx.conf')
    Execute(cert_placeholder_replace)
    File("/etc/nginx/sites-available/default",
         content = Template("nginx-sites-available-default.j2"))
    Logger.info("TSDProxy - Configuration completed.")

  def start(self, env):
    import params
    self.configure(env)

    Logger.info("TSDProxy - Starting service.")
    Execute('service nginx start')
    Logger.info("TSDProxy - Service is running.")

  def stop(self, env):
    Logger.info("TSDProxy - Stopping service.")
    Execute('service nginx stop')
    Logger.info("TSDProxy - Service is stopped.")

  def status(self, env):
    check_process_status('/var/run/nginx.pid')

if __name__ == "__main__":
  TSDProxy().execute()


