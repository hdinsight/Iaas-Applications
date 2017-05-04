
import datetime
import shared_ambari_installation

class IsHeadNodeAndAmsCollector(shared_ambari_installation.MockableService):
    def is_active_headnode(self):
        return True
        
    def is_ams_collector_host(self, ams_collector_host, this_host):
        return True

class SimulateAutoStartHosts(IsHeadNodeAndAmsCollector):

    def get_cluster_requests(self, ambari_cluster, *args, **kwargs):
        if 'request_status' in kwargs and kwargs['request_status'] == 'COMPLETED':
            start_time = (datetime.datetime.utcnow() - datetime.datetime.utcfromtimestamp(0)).total_seconds() * 1000
            return [type('', (object,), {'id': 100, 'start_time': start_time, 'request_context': 'Auto Start Host Components', 'status': 'COMPLETED', 'request_status': 'COMPLETED', 'resource_filters': [dict(hosts='dummyhost')]})]
        return []

    def get_delay_base_unit(self):
        return 0