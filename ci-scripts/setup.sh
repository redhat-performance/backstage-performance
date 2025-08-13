#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

echo -e "\n === Installing and setting up RHDH ===\n"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1090,SC1091
source "$(readlink -f "$SCRIPT_DIR"/../test.env)"

export GITHUB_TOKEN GITHUB_USER GITHUB_REPO QUAY_TOKEN KUBECONFIG PRE_LOAD_DB

GITHUB_TOKEN=$(cat /usr/local/ci-secrets/backstage-performance/github.token)
GITHUB_USER=$(cat /usr/local/ci-secrets/backstage-performance/github.user)
GITHUB_REPO=$(cat /usr/local/ci-secrets/backstage-performance/github.repo)
QUAY_TOKEN=$(cat /usr/local/ci-secrets/backstage-performance/quay.token)

export RHDH_DEPLOYMENT_REPLICAS=${RHDH_DEPLOYMENT_REPLICAS:-1}
export RHDH_DB_REPLICAS=${RHDH_DB_REPLICAS:-1}
export RHDH_DB_STORAGE=${RHDH_DB_STORAGE:-1Gi}
export RHDH_KEYCLOAK_REPLICAS=${RHDH_KEYCLOAK_REPLICAS:-1}

export API_COUNT=${API_COUNT:-1000}
export COMPONENT_COUNT=${COMPONENT_COUNT:-1000}
export BACKSTAGE_USER_COUNT=${BACKSTAGE_USER_COUNT:-1000}
export GROUP_COUNT=${GROUP_COUNT:-250}

ARTIFACT_DIR=$(readlink -f "${ARTIFACT_DIR:-.artifacts}")
mkdir -p "$ARTIFACT_DIR"

rate_limits_csv="${ARTIFACT_DIR}/gh-rate-limits-remaining.setup.csv"

echo "Starting a watch for GH rate limits remainig (setup)"
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
    echo "Stopping the watch for GH rate limits remainig (setup)"
    kill $rate_limit_exit || true
}
trap kill_rate_limits EXIT

echo "$(date -u -Ins) Running deployment script"
make ci-deploy
