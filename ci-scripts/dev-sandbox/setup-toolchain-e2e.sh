#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1090,SC1091
source "$(readlink -f "$SCRIPT_DIR/../../test.env")"

rootdir=$(readlink -f "$SCRIPT_DIR/../..")

export TMP_DIR
TMP_DIR=$(readlink -f "${TMP_DIR:-"$rootdir/.tmp"}")
mkdir -p "${TMP_DIR}"

wait_for_deployment() {
    deployment=$1
    ns=$2
    #Wait for the operator to get up and running
    retries=50
    until [[ $retries == 0 ]]; do
        kubectl get deployment/"$deployment" -n "$ns" >/dev/null 2>&1 && break
        echo "Waiting for $deployment to be created in $ns namespace"
        sleep 5
        retries=$((retries - 1))
    done
    kubectl rollout status -w deployment/"$deployment" -n "$ns"
}

# Ensure oc is loged in
export OPENSHIFT_API_TOKEN
OPENSHIFT_API_TOKEN=$(oc whoami -t) || (echo "a token is required to capture metrics, use 'oc login' to log into the cluster" && exit 1)

# Install Developer Sandbox
WSTC="$rootdir/.toolchain-e2e.git"
TOOLCHAIN_E2E_REPO=${TOOLCHAIN_E2E_REPO:-https://github.com/codeready-toolchain/toolchain-e2e}
TOOLCHAIN_E2E_BRANCH=${TOOLCHAIN_E2E_BRANCH:-master}
rm -rvf "$WSTC"
git clone "$TOOLCHAIN_E2E_REPO" "$WSTC"
cd "$WSTC" || exit
git reset --hard
git checkout "$TOOLCHAIN_E2E_BRANCH"
git pull

make dev-deploy-latest
