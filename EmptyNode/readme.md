# Add a new empty edge node to an existing HDInsight cluster

This template adds a new empty edgenode to an existing HDInsight cluster <br>
<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fhdinsight%2FIaas-Applications%2Fmaster%2FEmptyNode%2Fazuredeploy.json" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png"/>
</a>

The empty edge node virtual machine size must meet the worker node vm size requirements. The worker node vm size requirements are different from region to region. For more information, see <a href="https://docs.microsoft.com/azure/hdinsight/hdinsight-hadoop-provision-linux-clusters#cluster-types">Create HDInsight clusters</a>.

The template uses a simple "dummy" script to simulate application installation and prepare a clean empty edgenode and attach it to the cluster. 

For more information about creating and using edge node, see <a href="https://docs.microsoft.com/azure/hdinsight/hdinsight-apps-use-edge-node">Use empty edge nodes in HDInsight</a>
