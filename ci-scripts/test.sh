#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

echo -e "\n === Executing RHDH load test ===\n"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1090,SC1091
source "$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$SCRIPT_DIR"/../test.env)"

export SCENARIO RHDH_INSTALL_METHOD AUTH_PROVIDER RHDH_NAMESPACE

RHDH_NAMESPACE=${RHDH_NAMESPACE:-rhdh-performance}
RHDH_INSTALL_METHOD=${RHDH_INSTALL_METHOD:-helm}
AUTH_PROVIDER=${AUTH_PROVIDER:-keycloak}

# testing env
if [ "$RHDH_INSTALL_METHOD" == "olm" ]; then
    if [ "$AUTH_PROVIDER" == "keycloak" ]; then
        rhdh_route="rhdh"
    else
        rhdh_route="backstage-developer-hub"
    fi
elif [ "$RHDH_INSTALL_METHOD" == "helm" ]; then
    export RHDH_HELM_RELEASE_NAME RHDH_HELM_CHART

    RHDH_HELM_RELEASE_NAME=${RHDH_HELM_RELEASE_NAME:-rhdh}
    RHDH_HELM_CHART=${RHDH_HELM_CHART:-redhat-developer-hub}

    rhdh_route="$(oc -n "${RHDH_NAMESPACE}" get routes -l app.kubernetes.io/instance="${RHDH_HELM_RELEASE_NAME}" -o jsonpath='{.items[0].metadata.name}')"
else
    echo "Invalid RHDH install method: $RHDH_INSTALL_METHOD"
    exit 1
fi
export BASE_HOST
BASE_HOST="https://$(oc get routes "$rhdh_route" -n "${RHDH_NAMESPACE}" -o jsonpath='{.spec.host}')"
# end-of testing env

ARTIFACT_DIR=$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "${ARTIFACT_DIR:-.artifacts}")
mkdir -p "${ARTIFACT_DIR}"

rate_limits_csv="${ARTIFACT_DIR}/gh-rate-limits-remaining.test.csv"

echo "Starting a watch for GH rate limits remainig (test)"
IFS="," read -ra kvs <<<"$(cat /usr/local/ci-secrets/backstage-performance/github.accounts)"
echo -n "Time" >"$rate_limits_csv"
for kv in "${kvs[@]}"; do
    IFS=":" read -ra name_token <<<"$kv"
    echo -n ";${name_token[0]}" >>"$rate_limits_csv"
done
echo >>"$rate_limits_csv"

while true; do
    timestamp=$(printf "%s" "$(date -u +'%FT%T')")
    echo -n "$timestamp" >>"$rate_limits_csv"
    for kv in "${kvs[@]}"; do
        IFS=":" read -ra name_token <<<"$kv"
        rate=$(curl -s -H "Accept: application/vnd.github+json" -H "Authorization: token ${name_token[1]}" -H "X-GitHub-Api-Version: 2022-11-28" 'https://api.github.com/rate_limit' | jq -rc '(.rate.remaining|tostring)')
        echo -n ";$rate" >>"$rate_limits_csv"
    done
    echo >>"$rate_limits_csv"
    sleep 10s
done &

rate_limit_exit=$!
kill_rate_limits() {
    echo "Stopping the watch for GH rate limits remainig (test)"
    kill $rate_limit_exit
}
trap kill_rate_limits EXIT

echo "$(date -u -Ins) Running the test"
make ci-run
