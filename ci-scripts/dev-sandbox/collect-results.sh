#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1090,SC1091
source "$(readlink -m "$SCRIPT_DIR/../../test.env")"

rootdir=$(readlink -m "$SCRIPT_DIR/../..")

export ARTIFACT_DIR
ARTIFACT_DIR="${ARTIFACT_DIR:-"$rootdir/.artifacts"}"

export TMP_DIR
TMP_DIR=$(readlink -m "${TMP_DIR:-"$rootdir/.tmp"}")
mkdir -p "${TMP_DIR}"

cli="oc"

out=$ARTIFACT_DIR/summary.csv
rm -rvf "$out"
while read -r baseline_csv; do
    while read -r metrics; do
        while IFS="," read -r -a tokens; do
            metric="${tokens[0]}"
            echo -n "${metric}" >>"$out"
            for run_csv in $(find "$ARTIFACT_DIR/dev-sandbox" -type f -regex '.*\(run[0-9]*\|baseline\).csv' | sort -V); do
                # shellcheck disable=SC2001
                run_id=$(sed -e 's,.*\(run[0-9]*\|baseline\).csv,\1,g' <<<"$run_csv")
                if [ "$metric" == "Item" ]; then
                    echo -n ",$run_id" >>"$out"
                else
                    echo -n ",$(grep "$metric" "$run_csv" | sed -e 's/.*,\(.*\)/\1/g')" >>"$out"
                fi
            done
            echo >>"$out"
        done <<<"$metrics"
    done <"$baseline_csv"
done <<<"$(find "${ARTIFACT_DIR}/dev-sandbox/" -name '*baseline.csv')"

while read -r baseline_counts_csv; do
    while read -r metrics; do
        while IFS="," read -r -a tokens; do
            metric="${tokens[0]}"
            echo -n "${metric}" >>"$out"
            for run_csv in $(find "$ARTIFACT_DIR/dev-sandbox" -type f -regex '.*\(run[0-9]*\|baseline\)-counts-post.csv' | sort -V); do
                echo -n ",$(grep "$metric" "$run_csv" | sed -e 's/.*,\(.*\)/\1/g')" >>"$out"
            done
            echo >>"$out"
        done <<<"$metrics"
    done <"$baseline_counts_csv"
done <<<"$(find "${ARTIFACT_DIR}/dev-sandbox/" -name '*baseline-counts-post.csv')"

echo "$(date --utc -Ins) Setting up tool to collect monitoring data"

PYTHON_VENV_DIR="$rootdir/.venv"
python3 -m venv "$PYTHON_VENV_DIR"
set +u
# shellcheck disable=SC1090,SC1091
source "$PYTHON_VENV_DIR/bin/activate"
set -u
python3 -m pip install --quiet -U pip
python3 -m pip install --quiet -e "git+https://github.com/redhat-performance/opl.git#egg=opl-rhcloud-perf-team-core&subdirectory=core"
python3 -m pip install --quiet -U csvkit
set +u
deactivate
set -u

echo "$(date --utc -Ins) Collecting monitoring data"
set +u
# shellcheck disable=SC1090,SC1091
source "$PYTHON_VENV_DIR/bin/activate"
set -u

monitoring_collection_data="${ARTIFACT_DIR}/benchmark.json"
monitoring_collection_log=$ARTIFACT_DIR/monitoring-collection.log
monitoring_collection_dir=$ARTIFACT_DIR/monitoring-collection-raw-data-dir
mkdir -p "$monitoring_collection_dir"

mstart=$(date --utc --date "$(cat "${ARTIFACT_DIR}/benchmark-before")" --iso-8601=seconds)
mend=$(date --utc --date "$(cat "${ARTIFACT_DIR}/benchmark-after")" --iso-8601=seconds)
mhost=$(kubectl -n openshift-monitoring get route -l app.kubernetes.io/name=thanos-query -o json | jq --raw-output '.items[0].spec.host')
status_data.py \
    --status-data-file "$monitoring_collection_data" \
    --set \
    name="RHDH on Developer Sandbox Benchmark" \
    -d &>"$monitoring_collection_log"
status_data.py \
    --status-data-file "$monitoring_collection_data" \
    --additional "$SCRIPT_DIR/metrics-config.yaml" \
    --monitoring-start "$mstart" \
    --monitoring-end "$mend" \
    --monitoring-raw-data-dir "$monitoring_collection_dir" \
    --prometheus-host "https://$mhost" \
    --prometheus-port 443 \
    --prometheus-token "$($cli whoami -t)" \
    -d &>>"$monitoring_collection_log"

while read -r metric_csv; do
    {
        tmp_csv="$metric_csv.tmp"
        mv -f "$metric_csv" "$tmp_csv"
        echo "Processing $metric_csv"
        while read -r line; do
            IFS=',' read -ra tokens <<<"$line"
            timestamp="${tokens[0]}"
            value="${tokens[1]}"
            if [[ $line =~ ^timestamp ]]; then
                echo "$timestamp;$value"
            else
                echo "$(date -d "@$timestamp" --utc "+%F %T");$value"
            fi
        done <"$tmp_csv" >>"$metric_csv"
        rm -f "$tmp_csv"
    } &
done <<<"$(find "$monitoring_collection_dir" -name '*.csv')"

wait

csvjoin -c timestamp -d ";" --datetime-format "%F %T" "$monitoring_collection_dir"/*.csv >"$ARTIFACT_DIR/metrics-all.csv"
