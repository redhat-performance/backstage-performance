#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

echo -e "\n === Collecting test results and metrics for RHDH scalability test ===\n"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PYTHON_VENV_DIR="$SCRIPT_DIR/../../.venv"
python3 -m venv "$PYTHON_VENV_DIR"
set +u
# shellcheck disable=SC1090,SC1091
source "$PYTHON_VENV_DIR/bin/activate"
set -u
python3 -m pip install --quiet -U pip
python3 -m pip install --quiet -r "$SCRIPT_DIR/../../requirements.txt"
# shellcheck disable=SC1090,SC1091
source "$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$SCRIPT_DIR"/../../test.env)"

ARTIFACT_DIR=$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "${ARTIFACT_DIR:-.artifacts}")
mkdir -p "$ARTIFACT_DIR"

SCALABILITY_ARTIFACTS="$ARTIFACT_DIR/scalability"
mkdir -p "$SCALABILITY_ARTIFACTS"

read -ra workers <<<"${SCALE_WORKERS:-5}"

read -ra active_users_spawn_rate <<<"${SCALE_ACTIVE_USERS_SPAWN_RATES:-1:1 200:40}"

read -ra bs_users_groups <<<"${SCALE_BS_USERS_GROUPS:-1:1 10000:2500}"

read -ra rbac_policy_size <<<"${SCALE_RBAC_POLICY_SIZE:-10000}"

read -ra catalog_apis_components <<<"${SCALE_CATALOG_SIZES:-1:1 10000:10000}"

read -ra rhdh_replicas <<<"${SCALE_REPLICAS:-1:1}"

read -ra db_storages <<<"${SCALE_DB_STORAGES:-1Gi 2Gi}"

read -ra cpu_requests_limits <<<"${SCALE_CPU_REQUESTS_LIMITS:-:}"

read -ra memory_requests_limits <<<"${SCALE_MEMORY_REQUESTS_LIMITS:-:}"

csv_delim=";"
csv_delim_quoted="\"$csv_delim\""

echo "Collecting scalability data"
counter=1
rhdh_version=""
for w in "${workers[@]}"; do
    for r_c in "${rhdh_replicas[@]}"; do
        IFS=":" read -ra tokens <<<"${r_c}"
        r="${tokens[0]}"
        [[ "${#tokens[@]}" == 1 ]] && dbr="" || dbr="${tokens[1]}"
        for bu_bg in "${bs_users_groups[@]}"; do
            IFS=":" read -ra tokens <<<"${bu_bg}"
            bu="${tokens[0]}"                                        # backstage users
            [[ "${#tokens[@]}" == 1 ]] && bg="" || bg="${tokens[1]}" # backstage groups
            for rbs in "${rbac_policy_size[@]}"; do
                for s in "${db_storages[@]}"; do
                    for au_sr in "${active_users_spawn_rate[@]}"; do
                        IFS=":" read -ra tokens <<<"${au_sr}"
                        active_users=${tokens[0]}
                        output="$ARTIFACT_DIR/scalability_c-${r}r-${dbr}dbr-db_${s}-${bu}bu-${bg}bg-${rbs}rbs-${w}w-${active_users}u-${counter}.csv"
                        header="CatalogSize${csv_delim}Apis${csv_delim}Components${csv_delim}MaxActiveUsers${csv_delim}AverageRPS${csv_delim}MaxRPS${csv_delim}AverageRT${csv_delim}MaxRT${csv_delim}Failures${csv_delim}FailRate${csv_delim}DBStorageUsed${csv_delim}DBStorageAvailable${csv_delim}DBStorageCapacity"
                        for cr_cl in "${cpu_requests_limits[@]}"; do
                            IFS=":" read -ra tokens <<<"${cr_cl}"
                            cr="${tokens[0]}"                                        # cpu requests
                            [[ "${#tokens[@]}" == 1 ]] && cl="" || cl="${tokens[1]}" # cpu limits
                            for mr_ml in "${memory_requests_limits[@]}"; do
                                IFS=":" read -ra tokens <<<"${mr_ml}"
                                mr="${tokens[0]}"                                        # memory requests
                                [[ "${#tokens[@]}" == 1 ]] && ml="" || ml="${tokens[1]}" # memory limits
                                [[ -f "${output}" ]] || echo "$header" >"$output"
                                for a_c in "${catalog_apis_components[@]}"; do
                                    IFS=":" read -ra tokens <<<"${a_c}"
                                    a="${tokens[0]}"                                       # apis
                                    [[ "${#tokens[@]}" == 1 ]] && c="" || c="${tokens[1]}" # components
                                    index="${r}r-${dbr}dbr-db_${s}-${bu}bu-${bg}bg-${rbs}rbs-${w}w-${cr}cr-${cl}cl-${mr}mr-${ml}ml-${a}a-${c}c"
                                    iteration="${index}/test/${counter}/${active_users}u"
                                    (( counter += 1 ))
                                    echo "[$iteration] Looking for benchmark.json..."
                                    benchmark_json="$(find "${ARTIFACT_DIR}" -name benchmark.json | grep "$iteration" || true)"
                                    if [ -n "$benchmark_json" ]; then
                                        benchmark_json="$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$benchmark_json")"
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
                                        + $csv_delim_quoted + (.measurements.cluster.pv_stats.test.\"rhdh-postgresql\".used_bytes.max | tostring) \
                                        + $csv_delim_quoted + (.measurements.cluster.pv_stats.test.\"rhdh-postgresql\".available_bytes.min | tostring) \
                                        + $csv_delim_quoted + (.measurements.cluster.pv_stats.test.\"rhdh-postgresql\".capacity_bytes.max | tostring)"
                                        sed -Ee 's/: ([0-9]+\.[0-9]*[X]+[0-9e\+-]*|[0-9]*X+[0-9]*\.[0-9e\+-]*|[0-9]*X+[0-9]*\.[0-9]*X+[0-9e\+-]+)/: "\1"/g' "$benchmark_json" | jq -rc "$jq_cmd" >>"$output"
                                        if [ -z "$rhdh_version" ]; then
                                            rhdh_version=$(jq -r '.metadata.image."konflux.additional-tags" | split(", ") | map(select(test("[0-9]\\.[0-9]-[0-9]+"))) | .[0]' "$benchmark_json" || true)
                                        fi
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
done

echo "Collecting scalability summary"
./ci-scripts/runs-to-csv.sh "$ARTIFACT_DIR" >"$ARTIFACT_DIR/summary.csv"

echo "Generating RHDH performance summary charts"
metrics="RPS_Avg \
RPS_Max \
RHDH_CPU_Avg \
RHDH_CPU_Max \
RHDH_Memory_Avg \
RHDH_Memory_Max \
RHDH_DB_CPU_Avg \
RHDH_DB_CPU_Max \
RHDH_DB_Memory_Avg \
RHDH_DB_Memory_Max \
Failures \
Fail_Ratio_Avg \
Response_Time_Avg \
Response_Time_Max \
Components_Response_Time_Avg \
Components_Response_Time_Max \
ComponentsOwnedByUserGroup_Response_Time_Avg \
ComponentsOwnedByUserGroup_Response_Time_Max \
RHDH_DB_Populate_Storage_Used \
RHDH_DB_Test_Storage_Used \
DeployDuration \
PopulateDuration \
PopulateUsersGroupsDuration \
PopulateCatalogDuration \
Duration \
Orchestrator_Workflow_Overview_Response_Time_Avg \
Orchestrator_Workflow_Overview_Response_Time_Max \
Orchestrator_Workflow_Execute_Response_Time_Avg \
Orchestrator_Workflow_Execute_Response_Time_Max \
Orchestrator_Workflow_Instance_by_Id_Response_Time_Avg \
Orchestrator_Workflow_Instance_by_Id_Response_Time_Max \
Orchestrator_Workflow_All_Instances_Response_Time_Avg \
Orchestrator_Workflow_All_Instances_Response_Time_Max"

# Metrics
for x_axis_scale_label in "ActiveUsers:linear:Active Users" "RBAC_POLICY_SIZE:log:RBAC Policy Size" "Iteration:linear:Iteration" "CATALOG_SIZE:linear:Catalog Size" "COMPONENT_COUNT:linear:Component Count" "API_COUNT:linear:API Count"; do
    IFS=":" read -ra tokens <<<"${x_axis_scale_label}"
    xa="${tokens[0]}"                                         # x_axis
    [[ "${#tokens[@]}" -lt 2 ]] && sc="" || sc="${tokens[1]}" # scale
    [[ "${#tokens[@]}" -lt 2 ]] && xn="" || xn="${tokens[2]}" # x_label
    #shellcheck disable=SC2086
    python3 ./ci-scripts/scalability/rhdh-perf-chart.py --current "$ARTIFACT_DIR/summary.csv" --current-version "$rhdh_version" --metrics $metrics --metrics-metadata "$SCRIPT_DIR/rhdh-perf-chart_metric-metadata.yaml" --x-axis "$xa" --x-scale "$sc" --x-label "$xn" --y-scale "$sc" --scenario "$xn" --output-dir "$ARTIFACT_DIR"
done

echo "Collecting error reports"
find "$ARTIFACT_DIR/scalability" -name error-report.txt | sort -V | while IFS= read -r error_report; do
    # shellcheck disable=SC2001
    echo "$error_report" | sed -e 's,.*/scalability/\([^/]\+\)/test/\([^/]\+\)/error-report.txt.*,[\1/\2],g'
    cat "$error_report"
done >"$ARTIFACT_DIR/error-report.txt"
