# Install Hue as an HDInsight Iaas Cluster Application

Installs Hue as an Iaas Cluster Application on an existing cluster -<br>
<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fazure%2Fazure-quickstart-templates%2Fmaster%2Fhdinsight-linux-with-hue-on-edge-node%2Fazuredeploy.json" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png"/>
</a>

Template installs Hue as an Iaas Cluster Application on an existing cluster. 
The Hue dashboard is accessible via Https by using the cluster username and password.
To access the Hue dashboard, go to the cluster in the Azure portal and click on the Apps pane.

Additionally, the edge node has WebWasb, a WebHDFS implementation over the WASB Storage System. <br />
WebWasb allows you to access and execute commands against the default WASB container of the cluster using the WebHDFS interface.<br />

From the new edge node, WebWasb can be accessed using localhost as the hostname and 50073 as the port name.
As an example, if you wanted to list all files and directories at the root of the cluster's storage account, you could execute <pre>curl http://localhost:50073/WebWasb/webhdfs/v1/?op=LISTSTATUS</pre>

