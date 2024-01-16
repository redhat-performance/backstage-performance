#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

echo -e "\n === Collecting test results and metrics for RHDH scalability test ===\n"

ARTIFACT_DIR=$(readlink -m "${ARTIFACT_DIR:-.artifacts}")
mkdir -p "$ARTIFACT_DIR"

read -ra workers <<<"${SCALE_WORKERS:-5}"

read -ra active_users_spawn_rate <<<"${SCALE_ACTIVE_USERS_SPAWN_RATES:-1:1 200:40}"

read -ra bs_users_groups <<<"${SCALE_BS_USERS_GROUPS:-1:1 15000:5000}"

read -ra catalog_sizes <<<"${SCALE_CATALOG_SIZES:-1 10000}"

read -ra replicas <<<"${SCALE_REPLICAS:-5}"

read -ra db_storages <<<"${SCALE_DB_STORAGES:-1Gi 2Gi}"

read -ra cpu_requests_limits <<<"${SCALE_CPU_REQUESTS_LIMITS:-:}"

read -ra memory_requests_limits <<<"${SCALE_MEMORY_REQUESTS_LIMITS:-:}"

csv_delim=";"
csv_delim_quoted="\"$csv_delim\""

for w in "${workers[@]}"; do
    for r in "${replicas[@]}"; do
        for bu_bg in "${bs_users_groups[@]}"; do
            IFS=":" read -ra tokens <<<"${bu_bg}"
            bu="${tokens[0]}"
            bg="${tokens[1]}"
            for s in "${db_storages[@]}"; do
                for au_sr in "${active_users_spawn_rate[@]}"; do
                    IFS=":" read -ra tokens <<<"${au_sr}"
                    active_users=${tokens[0]}
                    output="$ARTIFACT_DIR/scalability_c-${r}r-db_${s}-${bu}bu-${bg}bg-${w}w-${active_users}u.csv"
                    header="CatalogSize${csv_delim}AverateRPS${csv_delim}MaxRPS${csv_delim}AverageRT${csv_delim}MaxRT${csv_delim}FailRate${csv_delim}DBStorageUsed${csv_delim}DBStorageAvailable${csv_delim}DBStorageCapacity"
                    for cr_cl in "${cpu_requests_limits[@]}"; do
                        IFS=":" read -ra tokens <<<"${cr_cl}"
                        cr="${tokens[0]}"
                        cl="${tokens[1]}"
                        for mr_ml in "${memory_requests_limits[@]}"; do
                            IFS=":" read -ra tokens <<<"${mr_ml}"
                            mr="${tokens[0]}"
                            ml="${tokens[1]}"
                            echo "$header" >"$output"
                            for c in "${catalog_sizes[@]}"; do
                                index="${r}r-db_${s}-${bu}bu-${bg}bg-${w}w-${cr}cr-${cl}cl-${mr}mr-${ml}ml-${c}c"
                                benchmark_json="$(find "${ARTIFACT_DIR}" -name benchmark.json | grep "$index" || true)"
                                echo -n "$c" >>"$output"
                                if [ -n "$benchmark_json" ]; then
                                    echo "Gathering data from $benchmark_json"
                                    jq_cmd="$csv_delim_quoted + (.results.\"locust-operator\".locust_requests_current_rps_Aggregated.mean | tostring) \
                                + $csv_delim_quoted + (.results.\"locust-operator\".locust_requests_current_rps_Aggregated.max | tostring) \
                                + $csv_delim_quoted + (.results.\"locust-operator\".locust_requests_avg_response_time_Aggregated.mean | tostring) \
                                + $csv_delim_quoted + (.results.\"locust-operator\".locust_requests_avg_response_time_Aggregated.max | tostring) \
                                + $csv_delim_quoted + (.results.\"locust-operator\".locust_requests_fail_ratio_Aggregated.mean | tostring) \
                                + $csv_delim_quoted + (.measurements.cluster.pv_stats.populate.\"data-rhdh-postgresql-primary-0\".used_bytes.max | tostring) \
                                + $csv_delim_quoted + (.measurements.cluster.pv_stats.populate.\"data-rhdh-postgresql-primary-0\".available_bytes.min | tostring) \
                                + $csv_delim_quoted + (.measurements.cluster.pv_stats.populate.\"data-rhdh-postgresql-primary-0\".capacity_bytes.max | tostring)"
                                    sed -Ee 's/: ([0-9]+\.[0-9]*[X]+[0-9e\+-]*|[0-9]*X+[0-9]*\.[0-9e\+-]*|[0-9]*X+[0-9]*\.[0-9]*X+[0-9e\+-]+)/: "\1"/g' "$benchmark_json" | jq -rc "$jq_cmd" >>"$output"
                                else
                                    for _ in $(seq 1 "$(echo "$header" | tr -cd "$csv_delim" | wc -c)"); do
                                        echo -n ";" >>"$output"
                                    done
                                    echo >>"$output"
                                fi
                            done
                        done
                    done
                done
            done
        done
    done
done
