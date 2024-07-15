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

WSTC=$(readlink -m "$rootdir/.toolchain-e2e.git")

export RHDH_INSTALL_METHOD=${RHDH_INSTALL_METHOD:-olm}

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

# testing env
if [ "$RHDH_INSTALL_METHOD" == "olm" ]; then
    rhdh_route="backstage-developer-hub"
elif [ "$RHDH_INSTALL_METHOD" == "helm" ]; then
    export RHDH_HELM_RELEASE_NAME RHDH_HELM_CHART

    RHDH_HELM_RELEASE_NAME=${RHDH_HELM_RELEASE_NAME:-rhdh}
    RHDH_HELM_CHART=${RHDH_HELM_CHART:-redhat-developer-hub}

    rhdh_route="${RHDH_HELM_RELEASE_NAME}-${RHDH_HELM_CHART}"
else
    echo "Invalid RHDH install method: $RHDH_INSTALL_METHOD"
    exit 1
fi
export RHDH_BASE_URL
RHDH_BASE_URL="https://$(oc get routes "$rhdh_route" -n "${RHDH_NAMESPACE:-rhdh-performance}" -o jsonpath='{.spec.host}')"
# end-of testing env

envsubst <"$SCRIPT_DIR/rhdh-perf-workloads.template.yaml" >"$TMP_DIR/rhdh-perf.workloads.yaml"
template="${1:-"$TMP_DIR/rhdh-perf.workloads.yaml"}"
for r in $(seq -w 1 "${2:-10}"); do
    TEST_ID="run$r"
    echo "Running $TEST_ID"
    make clean-users
    collect_counts "$TEST_ID-counts-pre"
    cmd="go run setup/main.go --users 2000 --default 2000 --custom 2000 --template=$template $workloads --username $TEST_ID --testname=$TEST_ID --verbose --idler-timeout 15m"
    yes | $cmd |& tee "$TEST_ID.log" && out="tmp/results/$(date +%F_%T)-counts.csv"
    collect_counts "$TEST_ID-counts-post"
done
