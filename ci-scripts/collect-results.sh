#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

ARTIFACT_DIR=${ARTIFACT_DIR:-artifacts}
monitoring_collection_data=$ARTIFACT_DIR/benchmark.json
monitoring_collection_log=$ARTIFACT_DIR/monitoring-collection.log
monitoring_collection_dir=$ARTIFACT_DIR/monitoring-collection-raw-data-dir
mkdir -p "$monitoring_collection_dir"

PYTHON_VENV_DIR=.venv

echo "$(date --utc -Ins) Setting up tool to collect monitoring data"
python3 -m venv $PYTHON_VENV_DIR
set +u
source $PYTHON_VENV_DIR/bin/activate
set -u
python3 -m pip install --quiet -U pip
python3 -m pip install --quiet -e "git+https://github.com/redhat-performance/opl.git#egg=opl-rhcloud-perf-team-core&subdirectory=core"
set +u
deactivate
set -u

echo "$(date --utc -Ins) Collecting monitoring data"
set +u
source $PYTHON_VENV_DIR/bin/activate
set -u
mstart=$(date --utc --date "$(cat benchmark-before)" --iso-8601=seconds)
mend=$(date --utc --date "$(cat benchmark-after)" --iso-8601=seconds)
mhost=$(kubectl -n openshift-monitoring get route -l app.kubernetes.io/name=thanos-query -o json | jq --raw-output '.items[0].spec.host')
status_data.py \
    --status-data-file "$monitoring_collection_data" \
    --set \
        results.started="$(cat benchmark-before)" \
        results.ended="$(cat benchmark-after)" \
    -d &>"$monitoring_collection_log"
status_data.py \
    --status-data-file "$monitoring_collection_data" \
    --additional config/cluster_read_config.yaml \
    --monitoring-start "$mstart" \
    --monitoring-end "$mend" \
    --monitoring-raw-data-dir "$monitoring_collection_dir" \
    --prometheus-host "https://$mhost" \
    --prometheus-port 443 \
    --prometheus-token "$(oc whoami -t)" \
    -d &>>"$monitoring_collection_log"
set +u
deactivate
set -u
