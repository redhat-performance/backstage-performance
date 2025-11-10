#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

echo -e "\n === Collecting test results and metrics ===\n"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1090,SC1091
source "$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$SCRIPT_DIR"/../test.env)"

ARTIFACT_DIR=$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "${ARTIFACT_DIR:-.artifacts}")
mkdir -p "${ARTIFACT_DIR}"

export TMP_DIR

TMP_DIR=$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "${TMP_DIR:-.tmp}")
mkdir -p "${TMP_DIR}"

RHDH_NAMESPACE=${RHDH_NAMESPACE:-rhdh-performance}
ENABLE_PROFILING="${ENABLE_PROFILING:-false}"
RHDH_INSTALL_METHOD="${RHDH_INSTALL_METHOD:-helm}"
LOCUST_NAMESPACE="${LOCUST_NAMESPACE:-locust-operator}"
RHDH_METRIC="${RHDH_METRIC:-true}"
PSQL_EXPORT="${PSQL_EXPORT:-false}"
ENABLE_ORCHESTRATOR="${ENABLE_ORCHESTRATOR:-false}"

cli="oc"
clin="$cli -n $RHDH_NAMESPACE"

# Logs
gather_pod_logs() {
    log_dir=$1
    pods=$2
    namespace=$3
    mkdir -p "$log_dir"
    echo -e "\nCollecting logs from pods in '$namespace' namespace:"
    for pod in $pods; do
        echo "$pod"
        containers=$($cli -n "$namespace" get pod "$pod" -o json | jq -r '.spec.containers[].name')
        if $cli -n "$namespace" get pod "$pod" -o json | jq -e '.spec.initContainers? // empty' >/dev/null; then
            init_containers=$($cli -n "$namespace" get pod "$pod" -o json | jq -r '.spec.initContainers[].name // empty')
        else
            init_containers=""
        fi
        all_containers="$containers $init_containers"
        for container in $all_containers; do
            logfile_prefix="$log_dir/${pod##*/}.$container"
            echo -e " -> $logfile_prefix.log"
            $cli -n "$namespace" logs "$pod" -c "$container" --tail=-1 >&"$logfile_prefix.log" || true
            echo -e " -> $logfile_prefix.previous.log"
            $cli -n "$namespace" logs "$pod" -c "$container" --tail=-1 --previous=true >&"$logfile_prefix.previous.log" || true
        done
    done
}

pods="$(oc -n "$LOCUST_NAMESPACE" get pods -o json | jq -r '.items[] | select(.metadata.name | contains("locust-operator")).metadata.name')"
pods="$pods $(oc -n "$LOCUST_NAMESPACE" get pods -o json | jq -r '.items[] | select(.metadata.name | contains("test-worker")).metadata.name')"
pods="$pods $(oc -n "$LOCUST_NAMESPACE" get pods -o json | jq -r '.items[] | select(.metadata.name | contains("test-master")).metadata.name')"
gather_pod_logs "${ARTIFACT_DIR}/locust-logs" "$pods" "$LOCUST_NAMESPACE"

pods=""
for label in app.kubernetes.io/name=developer-hub app.kubernetes.io/name=postgresql; do
    for pod in $($clin get pods -l "$label" -o jsonpath='{.items[*].metadata.name}'); do
        pods="$pods $pod"
    done
done
gather_pod_logs "${ARTIFACT_DIR}/rhdh-logs" "$pods" "$RHDH_NAMESPACE"

if [ "$ENABLE_ORCHESTRATOR" == "true" ]; then
    pods=$($clin get pods -l app.kubernetes.io/component=serverless-workflow -o jsonpath='{.items[*].metadata.name}')
    gather_pod_logs "${ARTIFACT_DIR}/workflow-logs" "$pods" "$RHDH_NAMESPACE"
fi

monitoring_collection_data=$ARTIFACT_DIR/benchmark.json
monitoring_collection_log=$ARTIFACT_DIR/monitoring-collection.log
monitoring_collection_dir=$ARTIFACT_DIR/monitoring-collection-raw-data-dir
mkdir -p "$monitoring_collection_dir"

try_gather_file() {
    if [ -f "$1" ]; then
        cp -vf "$1" "${2:-$ARTIFACT_DIR}"
    else
        echo "WARNING: Tried to gather $1 but the file was not found!"
    fi
}

try_gather_dir() {
    if [ -d "$1" ]; then
        cp -rvf "$1" "${2:-$ARTIFACT_DIR}"
    else
        echo "WARNING: Tried to gather $1 but the directory was not found!"
    fi
}

try_gather_file "${TMP_DIR}/backstage.url"
try_gather_file "${TMP_DIR}/keycloak.url"
try_gather_file "${TMP_DIR}/chart-values.yaml"
try_gather_file "${TMP_DIR}/deploy-before"
try_gather_file "${TMP_DIR}/deploy-after"
try_gather_file "${TMP_DIR}/populate-before"
try_gather_file "${TMP_DIR}/populate-after"
try_gather_file "${TMP_DIR}/populate-users-groups-before"
try_gather_file "${TMP_DIR}/populate-users-groups-after"
try_gather_file "${TMP_DIR}/populate-catalog-before"
try_gather_file "${TMP_DIR}/populate-catalog-after"
try_gather_file "${TMP_DIR}/benchmark-before"
try_gather_file "${TMP_DIR}/benchmark-after"
try_gather_file "${TMP_DIR}/benchmark-scenario"
try_gather_file "${TMP_DIR}/create_group.log"
try_gather_file "${TMP_DIR}/create_user.log"
try_gather_file "${TMP_DIR}/get_token.log"
try_gather_file "${TMP_DIR}/get_rhdh_token.log"
try_gather_file "${TMP_DIR}/get_user_count.log"
try_gather_file "${TMP_DIR}/get_group_count.log"
try_gather_file "${TMP_DIR}/get_component_count.log"
try_gather_file "${TMP_DIR}/get_api_count.log"
try_gather_file "${TMP_DIR}/rbac-config.yaml"
try_gather_file "${TMP_DIR}/locust-k8s-operator.values.yaml"
try_gather_file load-test.log
try_gather_file postgresql.log
try_gather_dir "${TMP_DIR}/workflows"

# Metrics
PYTHON_VENV_DIR=.venv

echo "$(date -u -Ins) Setting up tool to collect monitoring data"
python3 -m venv $PYTHON_VENV_DIR
set +u
# shellcheck disable=SC1090,SC1091
source $PYTHON_VENV_DIR/bin/activate
set -u
python3 -m pip install --quiet -U pip
python3 -m pip install --quiet -e "git+https://github.com/redhat-performance/opl.git#egg=opl-rhcloud-perf-team-core&subdirectory=core"
set +u
deactivate
set -u

echo "$(date -u -Ins) Collecting monitoring data"
set +u
# shellcheck disable=SC1090,SC1091
source $PYTHON_VENV_DIR/bin/activate
set -u

timestamp_diff() {
    started=$(python3 -c "from datetime import datetime; s='$1'; s=s.replace(',', '.'); d, f=s.split('.'); frac, tz=f.split('+'); print(datetime.fromisoformat(f'{d}.{frac[:6]}+{tz}'))")
    ended=$(python3 -c "from datetime import datetime; s='$2'; s=s.replace(',', '.'); d, f=s.split('.'); frac, tz=f.split('+'); print(datetime.fromisoformat(f'{d}.{frac[:6]}+{tz}'))")
    python3 -c "from datetime import datetime; st = datetime.strptime('$started', '%Y-%m-%d %H:%M:%S.%f%z'); et = datetime.strptime('$ended', '%Y-%m-%d %H:%M:%S.%f%z'); diff = et - st; print(f'{diff.total_seconds():.9f}')"
}

metrics_config_dir="${ARTIFACT_DIR}/metrics-config"
mkdir -p "$metrics_config_dir"

collect_additional_metrics() {
    echo "$(date -u -Ins) Collecting metrics from $1"
    status_data.py \
        --status-data-file "$monitoring_collection_data" \
        --additional "$1" \
        --monitoring-start "$mstart" \
        --monitoring-end "$mend" \
        --monitoring-raw-data-dir "$monitoring_collection_dir" \
        --prometheus-host "https://$mhost" \
        --prometheus-port 443 \
        --prometheus-token "$($cli whoami -t)" \
        -d >>"$monitoring_collection_log" 2>&1
}

# populate phase
if [ "$PRE_LOAD_DB" == "true" ]; then
    start_ts="$(cat "${ARTIFACT_DIR}/populate-before")"
    mstart=$(python3 -c "from datetime import datetime, timezone;ts ='$start_ts';dt_object = datetime.fromisoformat(ts.replace(',', '.'));formatted_ts = dt_object.strftime('%Y-%m-%dT%H:%M:%S%z');print(formatted_ts);")
    end_ts="$(cat "${ARTIFACT_DIR}/populate-after")"
    mend=$(python3 -c "from datetime import datetime, timezone;ts ='$end_ts';dt_object = datetime.fromisoformat(ts.replace(',', '.'));formatted_ts = dt_object.strftime('%Y-%m-%dT%H:%M:%S%z');print(formatted_ts);")
    mhost=$(kubectl -n openshift-monitoring get route -l app.kubernetes.io/name=thanos-query -o json | jq --raw-output '.items[0].spec.host')

    deploy_started=$(cat "${ARTIFACT_DIR}/deploy-before")
    deploy_ended=$(cat "${ARTIFACT_DIR}/deploy-after")
    deploy_duration="$(timestamp_diff "$deploy_started" "$deploy_ended")"

    populate_started=$(cat "${ARTIFACT_DIR}/populate-before")
    populate_ended=$(cat "${ARTIFACT_DIR}/populate-after")
    populate_duration="$(timestamp_diff "$populate_started" "$populate_ended")"

    populate_users_groups_started=$(cat "${ARTIFACT_DIR}/populate-users-groups-before")
    populate_users_groups_ended=$(cat "${ARTIFACT_DIR}/populate-users-groups-after")
    populate_users_groups_duration="$(timestamp_diff "$populate_users_groups_started" "$populate_users_groups_ended")"

    populate_catalog_started=$(cat "${ARTIFACT_DIR}/populate-catalog-before")
    populate_catalog_ended=$(cat "${ARTIFACT_DIR}/populate-catalog-after")
    populate_catalog_duration="$(timestamp_diff "$populate_catalog_started" "$populate_catalog_ended")"
    echo "$(date -u -Ins) Collecting Populate phase metrics"
    status_data.py \
        --status-data-file "$monitoring_collection_data" \
        --set \
        measurements.timings.deploy.started="$deploy_started" \
        measurements.timings.deploy.ended="$deploy_ended" \
        measurements.timings.deploy.duration="$deploy_duration" \
        measurements.timings.populate.started="$populate_started" \
        measurements.timings.populate.ended="$populate_ended" \
        measurements.timings.populate.duration="$populate_duration" \
        measurements.timings.populate_users_groups.started="$populate_users_groups_started" \
        measurements.timings.populate_users_groups.ended="$populate_users_groups_ended" \
        measurements.timings.populate_users_groups.duration="$populate_users_groups_duration" \
        measurements.timings.populate_catalog.started="$populate_catalog_started" \
        measurements.timings.populate_catalog.ended="$populate_catalog_ended" \
        measurements.timings.populate_catalog.duration="$populate_catalog_duration" \
        -d >"$monitoring_collection_log" 2>&1
    envsubst <config/cluster_read_config.populate.yaml >"${metrics_config_dir}/cluster_read_config.populate.yaml"
    collect_additional_metrics "${metrics_config_dir}/cluster_read_config.populate.yaml"
    if [ "$PSQL_EXPORT" == "true" ]; then
        echo "$(date -u -Ins) Collecting Postgresql specific metrics (populate)"
        envsubst <config/cluster_read_config.populate.postgresql.yaml >"${metrics_config_dir}/cluster_read_config.populate.postgresql.yaml"
        collect_additional_metrics "${metrics_config_dir}/cluster_read_config.populate.postgresql.yaml" "$monitoring_collection_data"
    fi
    #NodeJS specific metrics
    if [ "$RHDH_METRIC" == "true" ]; then
        echo "$(date -u -Ins) Collecting NodeJS specific metrics (populate)"
        envsubst <config/cluster_read_config.populate.nodejs.yaml >"${metrics_config_dir}/cluster_read_config.populate.nodejs.yaml"
        collect_additional_metrics "${metrics_config_dir}/cluster_read_config.populate.nodejs.yaml"
    fi

fi
# test phase
start_ts="$(cat "${ARTIFACT_DIR}/benchmark-before")"
mstart=$(python3 -c "from datetime import datetime, timezone;ts ='$start_ts';dt_object = datetime.fromisoformat(ts.replace(',', '.'));formatted_ts = dt_object.strftime('%Y-%m-%dT%H:%M:%S%z');print(formatted_ts);")
end_ts="$(cat "${ARTIFACT_DIR}/benchmark-after")"
mend=$(python3 -c "from datetime import datetime, timezone;ts ='$end_ts';dt_object = datetime.fromisoformat(ts.replace(',', '.'));formatted_ts = dt_object.strftime('%Y-%m-%dT%H:%M:%S%z');print(formatted_ts);")

mhost=$(kubectl -n openshift-monitoring get route -l app.kubernetes.io/name=thanos-query -o json | jq --raw-output '.items[0].spec.host')
mversion=$(sed -n 's/^__version__ = "\(.*\)"/\1/p' "scenarios/$(cat "${ARTIFACT_DIR}/benchmark-scenario").py")
benchmark_started=$(cat "${ARTIFACT_DIR}/benchmark-before")
benchmark_ended=$(cat "${ARTIFACT_DIR}/benchmark-after")
echo "$(date -u -Ins) Collecting Test phase metrics"
status_data.py \
    --status-data-file "$monitoring_collection_data" \
    --set \
    measurements.timings.benchmark.started="$benchmark_started" \
    measurements.timings.benchmark.ended="$benchmark_ended" \
    measurements.timings.benchmark.duration="$(timestamp_diff "$benchmark_started" "$benchmark_ended")" \
    name="RHDH load test $(cat "${ARTIFACT_DIR}/benchmark-scenario")" \
    metadata.scenario.name="$(cat "${ARTIFACT_DIR}/benchmark-scenario")" \
    metadata.scenario.version="$mversion" \
    -d >"$monitoring_collection_log" 2>&1
envsubst <config/cluster_read_config.test.yaml >"${metrics_config_dir}/cluster_read_config.test.yaml"
collect_additional_metrics "${metrics_config_dir}/cluster_read_config.test.yaml"
#Scenario specific metrics
echo "$(date -u -Ins) Collecting Scenario specific metrics"
benchmark_scenario=$(cat "${ARTIFACT_DIR}/benchmark-scenario")
if [ -f "scenarios/$benchmark_scenario.metrics.yaml" ]; then
    envsubst <"scenarios/$benchmark_scenario.metrics.yaml" >"${metrics_config_dir}/$benchmark_scenario.metrics.yaml"
    collect_additional_metrics "${metrics_config_dir}/$benchmark_scenario.metrics.yaml"
fi
#Postgresql specific metrics
if [ "$PSQL_EXPORT" == "true" ]; then
    echo "$(date -u -Ins) Collecting Postgresql specific metrics (test)"
    envsubst <config/cluster_read_config.test.postgresql.yaml >"${metrics_config_dir}/cluster_read_config.test.postgresql.yaml"
    collect_additional_metrics "${metrics_config_dir}/cluster_read_config.test.postgresql.yaml"
fi
#NodeJS specific metrics
if [ "$RHDH_METRIC" == "true" ]; then
    echo "$(date -u -Ins) Collecting NodeJS specific metrics (test)"
    envsubst <config/cluster_read_config.test.nodejs.yaml >"${metrics_config_dir}/cluster_read_config.test.nodejs.yaml"
    collect_additional_metrics "${metrics_config_dir}/cluster_read_config.test.nodejs.yaml"
fi
set +u
deactivate
set -u

# NodeJS profiling
if [ "$RHDH_INSTALL_METHOD" == "helm" ] && ${ENABLE_PROFILING}; then
    cpu_profile_file="$ARTIFACT_DIR/rhdh.cpu.profile"
    memory_profile_file="$ARTIFACT_DIR/rhdh.heapsnapshot"
    pod="$($clin get pod -l app.kubernetes.io/name=developer-hub -o name)"
    echo "[INFO][$(date -u -Ins)] Collecting CPU profile into $cpu_profile_file"
    $clin exec "$pod" -c backstage-backend -- /bin/bash -c 'find /opt/app-root/src -name "*v8.log" -exec base64 -w0 {} \;' | base64 -d >"$cpu_profile_file"
    echo "[INFO][$(date -u -Ins)] Collecting heap snapshot into $memory_profile_file"
    # shellcheck disable=SC2016
    $clin exec "$pod" -c backstage-backend -- /bin/bash -c 'for i in $(ls /proc | grep "^[0-9]"); do if [ -f /proc/$i/cmdline ]; then if $(cat /proc/$i/cmdline | grep node); then kill -s USR1 $i; break; fi; fi; done'
    echo "[INFO][$(date -u -Ins)] Waiting for 3 minutes till the heap snapshot is written down"
    sleep 3m
    echo "[INFO][$(date -u -Ins)] Downloading heap snapshot..."
    $clin exec "$pod" -c backstage-backend -- /bin/bash -c 'find /opt/app-root/src -name "*.heapsnapshot" -exec base64 -w0 {} \;' | base64 -d >"$memory_profile_file"
fi

echo "$(date -u -Ins) Generating summary CSV"
./ci-scripts/runs-to-csv.sh "$ARTIFACT_DIR" >"$ARTIFACT_DIR/summary.csv"

echo "$(date -u -Ins) Collecting error reports"
# Error report
find "$ARTIFACT_DIR" -name load-test.log -print0 | sort -V | while IFS= read -r file; do
    if grep "Error report" "$file" >/dev/null; then
        tail -n +"$(grep -n "Error report" "$file" | head -n 1 | cut -d ":" -f 1)" "$file"
    else
        echo 'No errors found!'
    fi
done >"$ARTIFACT_DIR/error-report.txt"
