#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1090,SC1091
source "$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$SCRIPT_DIR/../../test.env")"

rootdir=$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$SCRIPT_DIR/../..")

export ARTIFACT_DIR
ARTIFACT_DIR="${ARTIFACT_DIR:-"$rootdir/.artifacts"}"

export TMP_DIR
TMP_DIR=$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "${TMP_DIR:-"$rootdir/.tmp"}")
mkdir -p "${TMP_DIR}"

WSTC=$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$rootdir/.toolchain-e2e.git")

export RHDH_INSTALL_METHOD=${RHDH_INSTALL_METHOD:-olm}
export RHDH_WORKLOADS_TEMPLATE_NAME=${RHDH_WORKLOADS_TEMPLATE_NAME:-default}
export RHDH_WORKLOADS_TEMPLATE=${RHDH_WORKLOADS_TEMPLATE:-$SCRIPT_DIR/rhdh-perf-workloads.$RHDH_WORKLOADS_TEMPLATE_NAME.template.yaml}

cd "$WSTC" || exit

collect_counts() {
    out="$WSTC/tmp/results/$(date +%F_%T)-${1:-counts}.csv"
    rm -rvf "$out"
    for i in backstages secrets configmaps pods jobs; do
        echo "$i,$(oc get "$i" -A -o name | wc -l)" | tee -a "$out"
    done
}

rm -rvf "$ARTIFACT_DIR/dev-sandbox"
mkdir -p "$ARTIFACT_DIR/dev-sandbox"
rm -rvf "$WSTC/tmp"
mkdir -p "$WSTC/tmp"
ln -s "$ARTIFACT_DIR/dev-sandbox" "$WSTC/tmp/results"

workloads=$(for i in $(yq '.workloads[]' "$SCRIPT_DIR/workloads.yaml"); do echo -n --workloads="$i"; done)

make clean-users
collect_counts "baseline-counts-pre"
echo "Running baseline..."
cmd="go run setup/main.go --users 1 --default 1 --custom 0 --username baseline --testname=baseline $workloads"
yes | $cmd
collect_counts "baseline-counts-post"

number_of_runs=${1:-10}
number_of_users_per_run=${2:-2000}
number_of_users_with_workloads_per_run=${3:-2000}

template="$TMP_DIR/rhdh-perf.workloads.yaml"
echo "Using $RHDH_WORKLOADS_TEMPLATE template --> $template"
envsubst <"$RHDH_WORKLOADS_TEMPLATE" >"$template"
date -u -Ins >"${ARTIFACT_DIR}/benchmark-before"
for r in $(seq -w 1 "$number_of_runs"); do
    TEST_ID="run$r"
    echo "Running $TEST_ID"
    make clean-users
    collect_counts "$TEST_ID-counts-pre"
    cmd="go run setup/main.go --users $number_of_users_per_run --default $number_of_users_per_run --custom $number_of_users_with_workloads_per_run --template=$template $workloads --username $TEST_ID --testname=$TEST_ID --verbose --idler-timeout 15s --skip-install-operators"
    yes | $cmd 2>&1| tee "$TEST_ID.log" && out="tmp/results/$(date +%F_%T)-counts.csv"
    collect_counts "$TEST_ID-counts-post"
done
date -u -Ins >"${ARTIFACT_DIR}/benchmark-after"
