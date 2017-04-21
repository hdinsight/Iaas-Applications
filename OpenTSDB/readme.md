# Create a HDInsight cluster with OpenTSDB installed and deployed + 1 edge node to act as an external proxy

This template creates a new HDInsight HBase cluster with OpenTSDB installed and deployed + 1 edge node to act as an external proxy

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fhdinsight%2FIaas-Applications%2Fmaster%2FOpenTSDB%2Fazuredeploy.json" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png"/>
</a>

OpenTSDB ([http://opentsdb.net/](http://opentsdb.net/)) is a high performance, open source storage engine that allows users to 'Store and serve massive amounts of time series data without losing granularity.'.

OpenTSDB uses Apache HBase to store its data. HBase is available in HDInsight as a pre-configured cluster type. This template provisions a new HDInsight HBase cluster with OpenTSDB installed and deployed to every HBase Region Server in the cluster. 

The OpenTSDB service is installed as a service of Ambari, which effectively makes OpenTSDB a full Platform As A Service (PaaS) offering. No manual configuration, management or monitoring is required to keep the service running as the integration with Ambari ensures that these functions are performed without manual intervention. Additionally, if desired, the OpenTSDB daemons (TSDs) may be configured and monitored via the Ambari web interface.

This template also installs a HTTP proxy on an 'Edge Node' which allows time-series collectors outside of the cluster (eg. IoT sensors) to be able to send metrics to the system. The OpenTSDB web UX is accessible via this proxy as well as through an Ambari View installed on the Ambari web interface.