#!/bin/bash

tsd_port=${1:-4242}
ams_collector_host=${2:-'headnodehost'}

curl http://localhost:$tsd_port/api/stats |
    jq --arg fqdn_host $(hostname -f) 'map(select(. as $metric |
    [
        { metric: "tsd.connectionmgr.connections" },
        { metric: "tsd.connectionmgr.exceptions" },
        { metric: "tsd.rpc.received" },
        { metric: "tsd.rpc.exceptions" },
        { metric: "tsd.http.latency_50pct", "tags": { "type": "all" } },
        { metric: "tsd.http.latency_75pct", "tags": { "type": "all" } },
        { metric: "tsd.http.latency_90pct", "tags": { "type": "all" } },
        { metric: "tsd.http.latency_95pct", "tags": { "type": "all" } },
        { metric: "tsd.rpc.errors" },
        { metric: "tsd.http.query.invalid_requests" },
        { metric: "tsd.http.query.exceptions" },
        { metric: "tsd.http.query.success" },
        { metric: "tsd.uid.cache-hit", "tags": { "kind": "metrics" } },
        { metric: "tsd.uid.cache-miss", "tags": { "kind": "metrics" } },
        { metric: "tsd.uid.cache-size", "tags": { "kind": "metrics" } },
        { metric: "tsd.uid.random-collisions", "tags": { "kind": "metrics" } },
        { metric: "tsd.uid.ids-used", "tags": { "kind": "metrics" } },
        { metric: "tsd.uid.ids-available", "tags": { "kind": "metrics" } },
        { metric: "tsd.hbase.region_clients.open" },
        { metric: "tsd.hbase.region_clients.idle_closed" },
        { metric: "tsd.compaction.duplicates" },
        { metric: "tsd.compaction.queue.size" },
        { metric: "tsd.compaction.errors" },
        { metric: "tsd.compaction.writes" },
        { metric: "tsd.compaction.deletes" }
    ] |
    .[] as $match | $metric | contains($match))) |
    {
        "metrics": [
            .[] | {
                "metricname": (.metric + if .tags.type then "." + .tags.type else if .tags.kind then "." + .tags.kind else if .tags.rpc then "." + .tags.rpc else "" end end end),
                "appid": "opentsdb",
                "hostname": $fqdn_host,
                "timestamp": 0,
                "type": "Long",
                "starttime": (.timestamp * 1000),
                "metrics": {(.timestamp * 1000 | tostring): (.value | tonumber)}
            }
        ]
    }' |
    curl -X POST -H "Content-Type: application/json" http://$ams_collector_host:6188/ws/v1/timeline/metrics -d @- 

