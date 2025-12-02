#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

ARTIFACT_DIR=$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "${ARTIFACT_DIR:-.artifacts}")
mkdir -p "${ARTIFACT_DIR}"

PRS="${PRS:-279 280 281 282 283 284 285 286 287 288 289 290 292 293 294 295}"
BRANCHES="${BRANCHES:-rhdh-v1.7.x main}"

CURRENT_VERSION=${CURRENT_VERSION:-1.8-164}
PREVIOUS_VERSION=${PREVIOUS_VERSION:-1.7.2}
CURRENT_BASE_VERSION=1.8
PREVIOUS_BASE_VERSION=1.7

gather_artifacts_from_ci() {
    for PR_NUMBER in ${PRS}; do
        for BRANCH in ${BRANCHES}; do

            echo
            echo "Trying to gather artifacts from PR ${PR_NUMBER} on branch ${BRANCH}..."

            ORG="redhat-performance"
            REPO="backstage-performance"
            TEST_NAME="mvp-scalability"

            JOB_NAME="pull-ci-${ORG}-${REPO}-${BRANCH}-${TEST_NAME}"

            BASE_URL="https://gcsweb-ci.apps.ci.l2s4.p1.openshiftapps.com/gcs/test-platform-results/pr-logs/pull/${ORG}_${REPO}/${PR_NUMBER}/${JOB_NAME}/"
            LATEST_BUILD=$(curl -sSL "${BASE_URL}/latest-build.txt" |
                grep -oE '[0-9]{19}' |
                sort -un |
                tail -1) || continue

            echo "Latest build ID: $LATEST_BUILD"

            BASE_GS_ARTIFACTS="test-platform-results/pr-logs/pull/${ORG}_${REPO}/${PR_NUMBER}/${JOB_NAME}/${LATEST_BUILD}/artifacts/${TEST_NAME}/${ORG}-${REPO}-scalability/artifacts"
            RHDH_VERSION=$(gcloud storage cat "gs://${BASE_GS_ARTIFACTS}/scalability/*/test/1/*/benchmark.json" | gunzip | jq -rc '.metadata.env.RHDH_HELM_CHART_VERSION') || continue
            echo "RHDH version: $RHDH_VERSION"

            SCALABILITY_SCENARIO=$(curl -sSL "https://api.github.com/repos/${ORG}/${REPO}/pulls/${PR_NUMBER}" | jq -rc '.head.ref')
            echo "Scalability scenario: $SCALABILITY_SCENARIO"

            output="${ARTIFACT_DIR}/.artifacts.${SCALABILITY_SCENARIO}"

            mkdir -p "${output}"
            echo "$RHDH_VERSION" >"$output/rhdh-version.txt"
            echo "$PR_NUMBER" >"$output/pr-number.txt"
            echo "$LATEST_BUILD" >"$output/latest-build.txt"

            gcloud storage cp -r "gs://test-platform-results/pr-logs/pull/${ORG}_${REPO}/${PR_NUMBER}/${JOB_NAME}/${LATEST_BUILD}/artifacts/${TEST_NAME}/${ORG}-${REPO}-scalability/artifacts/summary.csv" "$output" || continue
            echo "Artifacts gathered from PR ${PR_NUMBER} on branch ${BRANCH}"
        done
    done
}

generate_rhdh_perf_charts() {

    PREVIOUS_DIR=${PREVIOUS_DIR:-}
    CURRENT_DIR=${CURRENT_DIR:-}
    SCENARIO=${SCENARIO:-}

    echo "$(date -u -Ins) Generating RHDH performacne charts for scenario $SCENARIO ($CURRENT_VERSION vs $PREVIOUS_VERSION)"

    OUTPUT_DIR=${OUTPUT_DIR:-.backstage-perf-charts}

    metrics="RPS_Avg \
RPS_Max \
Response_Time_Avg \
Response_Time_Max \
Failures \
Fail_Ratio_Avg \
RHDH_CPU_Avg \
RHDH_CPU_Max \
RHDH_Memory_Avg \
RHDH_Memory_Max \
RHDH_DB_CPU_Avg \
RHDH_DB_CPU_Max \
RHDH_DB_Memory_Avg \
RHDH_DB_Memory_Max \
Components_Response_Time_Avg \
Components_Response_Time_Max \
ComponentsOwnedByUserGroup_Response_Time_Avg \
ComponentsOwnedByUserGroup_Response_Time_Max \
RHDH_DB_Populate_Storage_Used \
RHDH_DB_Test_Storage_Used \
Orchestrator_Workflow_Overview_Response_Time_Avg \
Orchestrator_Workflow_Overview_Response_Time_Max \
Orchestrator_Workflow_Execute_Response_Time_Avg \
Orchestrator_Workflow_Execute_Response_Time_Max \
Orchestrator_Workflow_Instance_by_Id_Response_Time_Avg \
Orchestrator_Workflow_Instance_by_Id_Response_Time_Max \
Orchestrator_Workflow_All_Instances_Response_Time_Avg \
Orchestrator_Workflow_All_Instances_Response_Time_Max \
DeployDuration \
PopulateDuration \
PopulateUsersGroupsDuration \
PopulateCatalogDuration \
Duration"

    for x_axis_scale_label in "ActiveUsers:linear:Active Users" "RBAC_POLICY_SIZE:log:RBAC Policy Size" "Iteration:linear:Iteration"; do
        IFS=":" read -ra tokens <<<"${x_axis_scale_label}"
        xa="${tokens[0]}"                                         # x_axis
        [[ "${#tokens[@]}" -lt 2 ]] && sc="" || sc="${tokens[1]}" # scale
        [[ "${#tokens[@]}" -lt 2 ]] && xn="" || xn="${tokens[2]}" # x_label
        if [ -n "$SCENARIO" ]; then
            xn="$xn ($SCENARIO)"
        fi
        #shellcheck disable=SC2086
        if [ -n "$PREVIOUS_DIR" ]; then
            python3 "$SCRIPT_DIR/scalability/rhdh-perf-chart.py" \
                --previous "$PREVIOUS_DIR/summary.csv" \
                --previous-version "$PREVIOUS_VERSION" \
                --current "$CURRENT_DIR/summary.csv" \
                --current-version "$CURRENT_VERSION" \
                --metrics $metrics \
                --metrics-metadata "./ci-scripts/scalability/rhdh-perf-chart_metric-metadata.yaml" \
                --x-axis "$xa" --x-scale "$sc" --x-label "$xn" --y-scale "$sc" --scenario "$xn" --output-dir "$OUTPUT_DIR"
        else
            python3 "$SCRIPT_DIR/scalability/rhdh-perf-chart.py" \
                --previous "$PREVIOUS_DIR/summary.csv" \
                --previous-version "$PREVIOUS_VERSION" \
                --current "$CURRENT_DIR/summary.csv" \
                --current-version "$CURRENT_VERSION" \
                --metrics $metrics \
                --metrics-metadata "./ci-scripts/scalability/rhdh-perf-chart_metric-metadata.yaml" \
                --x-axis "$xa" --x-scale "$sc" --x-label "$xn" --y-scale "$sc" --scenario "$xn" --output-dir "$OUTPUT_DIR"
        fi
    done
}

generate_rhdh_perf_charts_for_scenarios() {
    # Comparing current version with previous version for each scenario
    for s in max_concurrency max_concurrency_with_orchestrator max_concurrency_ha_2 rbac rbac_groups rbac_nested orchestrator orchestrator_ha_2; do

        export CURRENT_DIR="${ARTIFACT_DIR}/.artifacts.test-${CURRENT_BASE_VERSION}-${s}-${CURRENT_BASE_VERSION}"
        export PREVIOUS_DIR="${ARTIFACT_DIR}/.artifacts.test-${CURRENT_BASE_VERSION}-${s}-${PREVIOUS_BASE_VERSION}"

        export SCENARIO="$s"
        export OUTPUT_DIR="${ARTIFACT_DIR}/.backstage-perf-charts/$s"

        export CURRENT_VERSION PREVIOUS_VERSION
        CURRENT_VERSION=$(cat "${CURRENT_DIR}/rhdh-version.txt") || continue
        PREVIOUS_VERSION=$(cat "${PREVIOUS_DIR}/rhdh-version.txt") || continue

        generate_rhdh_perf_charts || continue
    done

    # Comparing orchestrator overhead
    export CURRENT_DIR="${ARTIFACT_DIR}/.artifacts.test-${CURRENT_BASE_VERSION}-max_concurrency_with_orchestrator-${CURRENT_BASE_VERSION}"
    export PREVIOUS_DIR="${ARTIFACT_DIR}/.artifacts.test-${CURRENT_BASE_VERSION}-max_concurrency-${CURRENT_BASE_VERSION}"

    export SCENARIO=max_concurrency_with_orchestrator_overhead
    export OUTPUT_DIR="${ARTIFACT_DIR}/.backstage-perf-charts/${SCENARIO}"
    export CURRENT_VERSION PREVIOUS_VERSION
    CURRENT_VERSION="Orchestrator<br>($(cat "${CURRENT_DIR}/rhdh-version.txt"))" || true
    PREVIOUS_VERSION="No orchestrator<br>($(cat "${PREVIOUS_DIR}/rhdh-version.txt"))" || true
    generate_rhdh_perf_charts || true

    # Comparing Orchestrator HA
    export CURRENT_DIR="${ARTIFACT_DIR}/.artifacts.test-${CURRENT_BASE_VERSION}-orchestrator_ha_2-${CURRENT_BASE_VERSION}"
    export PREVIOUS_DIR="${ARTIFACT_DIR}/.artifacts.test-${CURRENT_BASE_VERSION}-orchestrator-${CURRENT_BASE_VERSION}"

    export SCENARIO=orchestrator_ha_2_vs_1
    export OUTPUT_DIR="${ARTIFACT_DIR}/.backstage-perf-charts/${SCENARIO}"
    export CURRENT_VERSION PREVIOUS_VERSION
    CURRENT_VERSION="2 Replicas<br>($(cat "${CURRENT_DIR}/rhdh-version.txt"))" || true
    PREVIOUS_VERSION="1 Replica<br>($(cat "${PREVIOUS_DIR}/rhdh-version.txt"))" || true
    generate_rhdh_perf_charts || true

    # Comparing Max Concurrency HA
    export CURRENT_DIR="${ARTIFACT_DIR}/.artifacts.test-${CURRENT_BASE_VERSION}-max_concurrency_ha_2-${CURRENT_BASE_VERSION}"
    export PREVIOUS_DIR="${ARTIFACT_DIR}/.artifacts.test-${CURRENT_BASE_VERSION}-max_concurrency-${CURRENT_BASE_VERSION}"

    export SCENARIO=max_concurrency_ha_2_vs_1
    export OUTPUT_DIR="${ARTIFACT_DIR}/.backstage-perf-charts/${SCENARIO}"
    export CURRENT_VERSION PREVIOUS_VERSION
    CURRENT_VERSION="2 Replicas<br>($(cat "${CURRENT_DIR}/rhdh-version.txt"))" || true
    PREVIOUS_VERSION="1 Replica<br>($(cat "${PREVIOUS_DIR}/rhdh-version.txt"))" || true
    generate_rhdh_perf_charts || true
}

all() {
    gather_artifacts_from_ci
    generate_rhdh_perf_charts_for_scenarios
}

help() {
    echo "Usage: $0 [-a] [-g] [-c] [-h]"
    echo "  -a: Gather artifacts from CI and generate RHDH performance charts for all scenarios"
    echo "  -g: Gather artifacts from CI only"
    echo "  -c: Generate RHDH performance charts for all scenarios only"
    echo "  -h: Show this help message"
}

if [ $# -eq 0 ]; then
    help
fi

while getopts "agch" flag; do
    case "${flag}" in
    g)
        gather_artifacts_from_ci
        ;;
    c)
        generate_rhdh_perf_charts_for_scenarios
        ;;
    a)
        all
        ;;
    \? | h)
        help
        ;;
    esac
done
