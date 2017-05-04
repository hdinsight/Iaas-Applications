# Create a HDInsight HBase cluster with TitanDB installed and deployed on 1 edge node

This template creates a new HDInsight HBase cluster with TitanDB Graph Database [https://titan.thinkaurelius.com/](https://titan.thinkaurelius.com/) installed and deployed on a cluster edge node. TitanDB is configured to use the cluster's HBase deployment as its storage backend. The Titan endpoint is opened on port 8182 (by default) using the `HTTPChannelizer` (ie. REST) interface. 

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fhdinsight%2FIaas-Applications%2Fmaster%2FTitanDB%2Fazuredeploy.json">
    <img src="http://azuredeploy.net/deploybutton.png"/>
</a>

TitanDB ([https://titan.thinkaurelius.com/](https://titan.thinkaurelius.com/)) is a high performance, highly scalable open source graph database optimized for storing and querying graphs containing hundreds of billions of vertices and edges distributed across a multi-machine cluster. Titan is a transactional database that can support thousands of concurrent users executing complex graph traversals in real time.

TitanDB features a plugable storage layer. Apache HBase is available in HDInsight as a pre-configured cluster type. This template provisions a new HDInsight HBase cluster with TitanDB installed and deployed on a single edge node, using the cluster's HBase as the configured storage engine. 

The TitanDB service is installed as a service of Ambari, which effectively makes TitanDB a full Platform As A Service (PaaS) offering. No manual configuration, management or monitoring is required to keep the service running as the integration with Ambari ensures that these functions are performed without manual intervention. Additionally, if desired, the OpenTSDB daemons (TSDs) may be configured and monitored via the Ambari web interface.
