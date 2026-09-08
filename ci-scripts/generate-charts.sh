#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

echo -e "\n === Generating charts for RHDH test ===\n"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PYTHON_VENV_DIR="$SCRIPT_DIR/../.venv"
python3 -m venv "$PYTHON_VENV_DIR"
set +u
# shellcheck disable=SC1090,SC1091
source "$PYTHON_VENV_DIR/bin/activate"
set -u
python3 -m pip install --quiet -U pip
python3 -m pip install --quiet -r "$SCRIPT_DIR/../requirements.txt"
# shellcheck disable=SC1090,SC1091
source "$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$SCRIPT_DIR/../test.env")"

ARTIFACT_DIR=$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "${ARTIFACT_DIR:-.artifacts}")
mkdir -p "$ARTIFACT_DIR"

OUTPUT_DIR=$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "${OUTPUT_DIR:-$ARTIFACT_DIR}")
mkdir -p "$OUTPUT_DIR"

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
PopulateCatalogDuration \
Duration \
Orchestrator_Workflow_Overview_Response_Time_Avg \
Orchestrator_Workflow_Overview_Response_Time_Max \
Orchestrator_Workflow_Execute_Response_Time_Avg \
Orchestrator_Workflow_Execute_Response_Time_Max \
Orchestrator_Workflow_Instance_by_Id_Response_Time_Avg \
Orchestrator_Workflow_Instance_by_Id_Response_Time_Max \
Orchestrator_Workflow_All_Instances_Response_Time_Avg \
Orchestrator_Workflow_All_Instances_Response_Time_Max \
Catalog_Allow_Response_Time_Avg \
Catalog_Deny_Response_Time_Avg \
RBAC_Allow_Response_Time_Avg \
RBAC_Deny_Response_Time_Avg \
Scaffolder_Allow_Response_Time_Avg \
Scaffolder_Deny_Response_Time_Avg \
Orchestrator_Allow_Response_Time_Avg \
Orchestrator_Deny_Response_Time_Avg \
Auth_Policy_Response_Time_Avg \
LoginPageLoadedResponseTimeAvg \
LoginPageLoadedResponseTimeMax \
HomePageLoadedResponseTimeAvg \
HomePageLoadedResponseTimeMax \
CatalogPageLoadedResponseTimeAvg \
CatalogPageLoadedResponseTimeMax \
ComponentPageLoadedResponseTimeAvg \
ComponentPageLoadedResponseTimeMax \
CatalogTabNLoadedResponseTimeAvg \
CatalogTabNLoadedResponseTimeMax \
PageNLoadedResponseTimeAvg \
PageNLoadedResponseTimeMax \
E2EDurationAvg \
E2EDurationMax"

rhdh_version=""

benchmark_jsons="$(find "${ARTIFACT_DIR}" -name benchmark.json || true)"
if [ -n "$benchmark_jsons" ]; then
    for b_v in $benchmark_jsons; do
        rhdh_version=$(jq -r '.metadata.image."konflux.additional-tags" | if type == "string" then split(", ") | map(select(test("[0-9]\\.[0-9]-[0-9]+"))) | .[0] else empty end' "$b_v" || true)
        if [ -n "$rhdh_version" ]; then
            echo "Identified RHDH version: $rhdh_version"
            break
        fi
    done
else
    echo "WARN: Unable to find benchmark.json"
fi

if [ -z "$rhdh_version" ]; then
    echo "WARN: Unable to find RHDH version"
    rhdh_version="n/a"
fi

X_AXIS_SCALE_LABEL="${X_AXIS_SCALE_LABEL:-"ActiveUsers:linear:Active Users"}"

# Metrics
IFS=":" read -ra tokens <<<"${X_AXIS_SCALE_LABEL}"
xa="${tokens[0]}"                                         # x_axis
[[ "${#tokens[@]}" -lt 2 ]] && sc="" || sc="${tokens[1]}" # scale
[[ "${#tokens[@]}" -lt 2 ]] && xn="" || xn="${tokens[2]}" # x_label
#shellcheck disable=SC2086
python3 "$SCRIPT_DIR/scalability/rhdh-perf-chart.py" --current "$ARTIFACT_DIR/summary.csv" --current-version "$rhdh_version" --metrics $metrics --metrics-metadata "$SCRIPT_DIR/scalability/rhdh-perf-chart_metric-metadata.yaml" --x-axis "$xa" --x-scale "$sc" --x-label "$xn" --y-scale "$sc" --scenario "$xn" --output-dir "$OUTPUT_DIR"
