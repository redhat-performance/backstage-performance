#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

echo -e "\n === Collecting test results and metrics ===\n"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1090,SC1091
source "$(readlink -m "$SCRIPT_DIR"/../test.env)"

ARTIFACT_DIR=$(readlink -m "${ARTIFACT_DIR:-.artifacts}")
mkdir -p "${ARTIFACT_DIR}"

export TMP_DIR

TMP_DIR=$(readlink -m "${TMP_DIR:-.tmp}")
mkdir -p "${TMP_DIR}"

RHDH_NAMESPACE=${RHDH_NAMESPACE:-rhdh-performance}
ENABLE_PROFILING="${ENABLE_PROFILING:-false}"
RHDH_INSTALL_METHOD="${RHDH_INSTALL_METHOD:-helm}"

cli="oc"
clin="$cli -n $RHDH_NAMESPACE"

for label in app.kubernetes.io/name=developer-hub app.kubernetes.io/name=postgresql; do
    echo -e "\nCollecting logs from pods in '$RHDH_NAMESPACE' namespace with label '$label':"
    for pod in $($clin get pods -l "$label" -o name); do
        echo "$pod"
        logfile="${ARTIFACT_DIR}/${pod##*/}"
        echo -e " -> $logfile.log"
        $clin logs "$pod" --tail=-1 >&"$logfile.log" || true
        echo -e " -> $logfile.previous.log"
        $clin logs "$pod" --tail=-1 --previous=true >&"$logfile.previous.log" || true
    done
done

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
try_gather_file "${TMP_DIR}/benchmark-before"
try_gather_file "${TMP_DIR}/benchmark-after"
try_gather_file "${TMP_DIR}/benchmark-scenario"
try_gather_file "${TMP_DIR}/create_group.log"
try_gather_file "${TMP_DIR}/create_user.log"
try_gather_file "${TMP_DIR}/get_token.log"
try_gather_file load-test.log
try_gather_file postgresql.log

PYTHON_VENV_DIR=.venv

echo "$(date --utc -Ins) Setting up tool to collect monitoring data"
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

echo "$(date --utc -Ins) Collecting monitoring data"
set +u
# shellcheck disable=SC1090,SC1091
source $PYTHON_VENV_DIR/bin/activate
set -u
# populate phase
if [ "$PRE_LOAD_DB" == "true" ]; then
    mstart=$(date --utc --date "$(cat "${TMP_DIR}/populate-before")" --iso-8601=seconds)
    mend=$(date --utc --date "$(cat "${TMP_DIR}/populate-after")" --iso-8601=seconds)
    mhost=$(kubectl -n openshift-monitoring get route -l app.kubernetes.io/name=thanos-query -o json | jq --raw-output '.items[0].spec.host')
    status_data.py \
        --status-data-file "$monitoring_collection_data" \
        --additional config/cluster_read_config.populate.yaml \
        --monitoring-start "$mstart" \
        --monitoring-end "$mend" \
        --monitoring-raw-data-dir "$monitoring_collection_dir" \
        --prometheus-host "https://$mhost" \
        --prometheus-port 443 \
        --prometheus-token "$($cli whoami -t)" \
        -d &>>"$monitoring_collection_log"
fi
# test phase
mstart=$(date --utc --date "$(cat "${TMP_DIR}/benchmark-before")" --iso-8601=seconds)
mend=$(date --utc --date "$(cat "${TMP_DIR}/benchmark-after")" --iso-8601=seconds)
mhost=$(kubectl -n openshift-monitoring get route -l app.kubernetes.io/name=thanos-query -o json | jq --raw-output '.items[0].spec.host')
mversion=$(sed -n 's/^__version__ = "\(.*\)"/\1/p' "scenarios/$(cat "${TMP_DIR}/benchmark-scenario").py")
status_data.py \
    --status-data-file "$monitoring_collection_data" \
    --set \
    results.started="$(cat "${TMP_DIR}/benchmark-before")" \
    results.ended="$(cat "${TMP_DIR}/benchmark-after")" \
    name="RHDH load test $(cat "${TMP_DIR}/benchmark-scenario")" \
    metadata.scenario.name="$(cat "${TMP_DIR}/benchmark-scenario")" \
    metadata.scenario.version="$mversion" \
    -d &>"$monitoring_collection_log"
status_data.py \
    --status-data-file "$monitoring_collection_data" \
    --additional config/cluster_read_config.test.yaml \
    --monitoring-start "$mstart" \
    --monitoring-end "$mend" \
    --monitoring-raw-data-dir "$monitoring_collection_dir" \
    --prometheus-host "https://$mhost" \
    --prometheus-port 443 \
    --prometheus-token "$($cli whoami -t)" \
    -d &>>"$monitoring_collection_log"
#Scenario specific metrics
if [ -f "scenarios/$(cat "${TMP_DIR}/benchmark-scenario").metrics.yaml" ]; then
    status_data.py \
        --status-data-file "$monitoring_collection_data" \
        --additional "scenarios/$(cat "${TMP_DIR}/benchmark-scenario").metrics.yaml" \
        --monitoring-start "$mstart" \
        --monitoring-end "$mend" \
        --monitoring-raw-data-dir "$monitoring_collection_dir" \
        --prometheus-host "https://$mhost" \
        --prometheus-port 443 \
        --prometheus-token "$($cli whoami -t)" \
        -d &>>"$monitoring_collection_log"
fi
set +u
deactivate
set -u

# NodeJS profiling
if [ "$RHDH_INSTALL_METHOD" == "helm" ] && ${ENABLE_PROFILING}; then
    cpu_profile_file="$ARTIFACT_DIR/rhdh.cpu.profile"
    memory_profile_file="$ARTIFACT_DIR/rhdh.heapsnapshot"
    pod="$($clin get pod -l app.kubernetes.io/name=developer-hub -o name)"
    echo "[INFO][$(date --utc -Ins)] Collecting CPU profile into $cpu_profile_file"
    $clin exec "$pod" -c backstage-backend -- /bin/bash -c 'find /opt/app-root/src -name "*v8.log" -exec base64 -w0 {} \;' | base64 -d >"$cpu_profile_file"
    echo "[INFO][$(date --utc -Ins)] Collecting heap snapshot into $memory_profile_file"
    # shellcheck disable=SC2016
    $clin exec "$pod" -c backstage-backend -- /bin/bash -c 'for i in $(ls /proc | grep "^[0-9]"); do if [ -f /proc/$i/cmdline ]; then if $(cat /proc/$i/cmdline | grep node); then kill -s USR1 $i; break; fi; fi; done'
    echo "[INFO][$(date --utc -Ins)] Waiting for 3 minutes till the heap snapshot is written down"
    sleep 3m
    echo "[INFO][$(date --utc -Ins)] Downloading heap snapshot..."
    $clin exec "$pod" -c backstage-backend -- /bin/bash -c 'find /opt/app-root/src -name "*.heapsnapshot" -exec base64 -w0 {} \;' | base64 -d >"$memory_profile_file"
fi

./ci-scripts/runs-to-csv.sh "$ARTIFACT_DIR" >"$ARTIFACT_DIR/summary.csv"

# Error report
find "$ARTIFACT_DIR" -name load-test.log -print0 | sort -V | while IFS= read -r file; do
    if grep "Error report" "$file" >/dev/null; then
        tail -n +"$(grep -n "Error report" "$file" | head -n 1 | cut -d ":" -f 1)" "$file"
    else
        echo 'No errors found!'
    fi
done >"$ARTIFACT_DIR/error-report.txt"
