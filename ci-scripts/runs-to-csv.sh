#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

# Just a helper script to output CSV file based on all found benchmark.json files
headers="Build_ID,\
Started,\
Ended,\
Scenario,\
USERS,\
SPAWN_RATE,\
WORKERS,\
API_COUNT,\
COMPONENT_COUNT,\
BACKSTAGE_USER_COUNT,\
GROUP_COUNT,\
RHDH_DEPLOYMENT_REPLICAS,\
RHDH_RESOURCES_CPU_LIMITS,\
RHDH_RESOURCES_MEMORY_LIMITS,\
RHDH_DB_REPLICAS,\
RHDH_KEYCLOAK_REPLICAS,\
RHDH_Pods,\
RHDH_CPU_Avg,\
RHDH_CPU_Max,\
RHDH_Memory_Avg,\
RHDH_Memory_Max,\
RHDH_DB_Pods,\
RHDH_DB_CPU_Avg,\
RHDH_DB_CPU_Max,\
RHDH_DB_Memory_Avg,\
RHDH_DB_Memory_Max,\
RHDH_DB_Populate_Storage_Used,\
RHDH_DB_Populate_Storage_Available,\
RHDH_DB_Populate_Storage_Capacity,\
RHDH_DB_Test_Storage_Used,\
RHDH_DB_Test_Storage_Available,\
RHDH_DB_Test_Storage_Capacity,\
RPS_Avg,\
RPS_Max,\
Failures,\
Fail_Ratio_Avg,\
Response_Time_Min,\
Response_Time_Avg,\
Response_Time_Perc90,\
Response_Time_Perc99,\
Response_Time_Perc999,\
Response_Time_Max,\
Response_Size_Avg"
echo "$headers"

find "${1:-.}" -name benchmark.json -print0 | while IFS= read -r -d '' filename; do
    sed -Ee 's/: ([0-9]+\.[0-9]*[X]+[0-9e\+-]*|[0-9]*X+[0-9]*\.[0-9e\+-]*|[0-9]*X+[0-9]*\.[0-9]*X+[0-9e\+-]+)/: "\1"/g' "${filename}" |
        jq --raw-output '[
        .metadata.env.BUILD_ID,
        .results.started,
        .results.ended,
        .metadata.scenario.name,
        .metadata.env.USERS,
        .metadata.env.SPAWN_RATE,
        .metadata.env.WORKERS,
        .metadata.env.API_COUNT,
        .metadata.env.COMPONENT_COUNT,
        .metadata.env.BACKSTAGE_USER_COUNT,
        .metadata.env.GROUP_COUNT,
        .metadata.env.RHDH_DEPLOYMENT_REPLICAS,
        .metadata.env.RHDH_RESOURCES_CPU_LIMITS,
        .metadata.env.RHDH_RESOURCES_MEMORY_LIMITS,
        .metadata.env.RHDH_DB_REPLICAS,
        .metadata.env.RHDH_KEYCLOAK_REPLICAS,
        .measurements."rhdh-developer-hub".count_ready.mean,
        .measurements."rhdh-developer-hub".cpu.mean,
        .measurements."rhdh-developer-hub".cpu.max,
        .measurements."rhdh-developer-hub".memory.mean,
        .measurements."rhdh-developer-hub".memory.max,
        .measurements."rhdh-postgresql".count_ready.mean,
        .measurements."rhdh-postgresql".cpu.mean,
        .measurements."rhdh-postgresql".cpu.max,
        .measurements."rhdh-postgresql".memory.mean,
        .measurements."rhdh-postgresql".memory.max,
        .measurements.cluster.pv_stats.populate."rhdh-postgresql".used_bytes.max,
        .measurements.cluster.pv_stats.populate."rhdh-postgresql".available_bytes.min,
        .measurements.cluster.pv_stats.populate."rhdh-postgresql".capacity_bytes.max,
        .measurements.cluster.pv_stats.test."rhdh-postgresql".used_bytes.max,
        .measurements.cluster.pv_stats.test."rhdh-postgresql".available_bytes.min,
        .measurements.cluster.pv_stats.test."rhdh-postgresql".capacity_bytes.max,
        .results.Aggregated.locust_requests_current_rps.mean,
        .results.Aggregated.locust_requests_current_rps.max,
        .results.Aggregated.locust_requests_num_failures.max,
        .results.locust_requests_fail_ratio.mean,
        .results.Aggregated.locust_requests_avg_response_time.min,
        .results.Aggregated.locust_requests_avg_response_time.mean,
        .results.Aggregated.locust_requests_avg_response_time.percentile90,
        .results.Aggregated.locust_requests_avg_response_time.percentile99,
        .results.Aggregated.locust_requests_avg_response_time.percentile999,
        .results.Aggregated.locust_requests_avg_response_time.max,
        .results.Aggregated.locust_requests_avg_content_length.max
        ] | @csv' &&
        rc=0 || rc=1
    if [[ "$rc" -ne 0 ]]; then
        echo "ERROR failed on ${filename}"
    fi
done
