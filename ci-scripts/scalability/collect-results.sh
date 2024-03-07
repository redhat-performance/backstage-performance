#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

echo -e "\n === Collecting test results and metrics for RHDH scalability test ===\n"

ARTIFACT_DIR=$(readlink -m "${ARTIFACT_DIR:-.artifacts}")
mkdir -p "$ARTIFACT_DIR"

read -ra workers <<<"${SCALE_WORKERS:-5}"

read -ra active_users_spawn_rate <<<"${SCALE_ACTIVE_USERS_SPAWN_RATES:-1:1 200:40}"

read -ra bs_users_groups <<<"${SCALE_BS_USERS_GROUPS:-1:1 10000:2500}"

read -ra catalog_apis_components <<<"${SCALE_CATALOG_SIZES:-1:1 10000:10000}"

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
            bu="${tokens[0]}"                                        # backstage users
            [[ "${#tokens[@]}" == 1 ]] && bg="" || bg="${tokens[1]}" # backstage groups
            for s in "${db_storages[@]}"; do
                for au_sr in "${active_users_spawn_rate[@]}"; do
                    IFS=":" read -ra tokens <<<"${au_sr}"
                    active_users=${tokens[0]}
                    output="$ARTIFACT_DIR/scalability_c-${r}r-db_${s}-${bu}bu-${bg}bg-${w}w-${active_users}u.csv"
                    header="CatalogSize${csv_delim}Apis${csv_delim}Components${csv_delim}MaxActiveUsers${csv_delim}AverageRPS${csv_delim}MaxRPS${csv_delim}AverageRT${csv_delim}MaxRT${csv_delim}Failures${csv_delim}FailRate${csv_delim}DBStorageUsed${csv_delim}DBStorageAvailable${csv_delim}DBStorageCapacity"
                    for cr_cl in "${cpu_requests_limits[@]}"; do
                        IFS=":" read -ra tokens <<<"${cr_cl}"
                        cr="${tokens[0]}"                                        # cpu requests
                        [[ "${#tokens[@]}" == 1 ]] && cl="" || cl="${tokens[1]}" # cpu limits
                        for mr_ml in "${memory_requests_limits[@]}"; do
                            IFS=":" read -ra tokens <<<"${mr_ml}"
                            mr="${tokens[0]}"                                        # memory requests
                            [[ "${#tokens[@]}" == 1 ]] && ml="" || ml="${tokens[1]}" # memory limits
                            echo "$header" >"$output"
                            for a_c in "${catalog_apis_components[@]}"; do
                                IFS=":" read -ra tokens <<<"${a_c}"
                                a="${tokens[0]}"                                       # apis
                                [[ "${#tokens[@]}" == 1 ]] && c="" || c="${tokens[1]}" # components
                                index="${r}r-db_${s}-${bu}bu-${bg}bg-${w}w-${cr}cr-${cl}cl-${mr}mr-${ml}ml-${a}a-${c}c"
                                iteration="${index}/test/${active_users}u"
                                echo "[$iteration] Looking for benchmark.json..."
                                benchmark_json="$(find "${ARTIFACT_DIR}" -name benchmark.json | grep "$iteration" || true)"
                                if [ -n "$benchmark_json" ]; then
                                    benchmark_json="$(readlink -m "$benchmark_json")"
                                    echo "[$iteration] Gathering data from $benchmark_json"
                                    jq_cmd="\"$((a + c))\" \
                                        + $csv_delim_quoted + \"${a}\" \
                                        + $csv_delim_quoted + \"${c}\" \
                                        + $csv_delim_quoted + (.results.locust_users.max | tostring) \
                                        + $csv_delim_quoted + (.results.Aggregated.locust_requests_current_rps.mean | tostring) \
                                        + $csv_delim_quoted + (.results.Aggregated.locust_requests_current_rps.max | tostring) \
                                        + $csv_delim_quoted + (.results.Aggregated.locust_requests_avg_response_time.mean | tostring) \
                                        + $csv_delim_quoted + (.results.Aggregated.locust_requests_avg_response_time.max | tostring) \
                                        + $csv_delim_quoted + (.results.Aggregated.locust_requests_num_failures.max | tostring) \
                                        + $csv_delim_quoted + (.results.locust_requests_fail_ratio.mean | tostring) \
                                        + $csv_delim_quoted + (.measurements.cluster.pv_stats.test.\"data-rhdh-postgresql-primary-0\".used_bytes.max | tostring) \
                                        + $csv_delim_quoted + (.measurements.cluster.pv_stats.test.\"data-rhdh-postgresql-primary-0\".available_bytes.min | tostring) \
                                        + $csv_delim_quoted + (.measurements.cluster.pv_stats.test.\"data-rhdh-postgresql-primary-0\".capacity_bytes.max | tostring)"
                                    sed -Ee 's/: ([0-9]+\.[0-9]*[X]+[0-9e\+-]*|[0-9]*X+[0-9]*\.[0-9e\+-]*|[0-9]*X+[0-9]*\.[0-9]*X+[0-9e\+-]+)/: "\1"/g' "$benchmark_json" | jq -rc "$jq_cmd" >>"$output"
                                else
                                    echo "[$iteration] Unable to find benchmark.json"
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

./ci-scripts/runs-to-csv.sh "$ARTIFACT_DIR" >"$ARTIFACT_DIR/summary.csv"
