#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

# Just a helper script to output CSV file based on all found benchmark-tekton.json files

find . -name benchmark.json -print0 | while IFS= read -r -d '' filename; do 
    jq <"${filename}" --raw-output '[
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
        .results.Aggregated.locust_requests_current_rps.mean,
        .results.locust_requests_fail_ratio.mean,
        .results.Aggregated.locust_requests_avg_response_time.min,
        .results.Aggregated.locust_requests_avg_response_time.mean,
        .results.Aggregated.locust_requests_avg_response_time.percentile90,
        .results.Aggregated.locust_requests_avg_response_time.percentile99,
        .results.Aggregated.locust_requests_avg_response_time.percentile999,
        .results.Aggregated.locust_requests_avg_response_time.max
        ] | @csv' \
        && rc=0 || rc=1
    if [[ "$rc" -ne 0 ]]; then
        echo "ERROR failed on ${filename}"
    fi
done
