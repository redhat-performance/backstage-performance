#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

echo -e "\n === Executing RHDH load test ===\n"

export SCENARIO

# testing env
export HOST
HOST="https://$(oc get routes rhdh-developer-hub -n "${RHDH_NAMESPACE:-rhdh-performance}" -o jsonpath='{.spec.host}')"
# end-of testing env

ARTIFACT_DIR=${ARTIFACT_DIR:-artifacts}
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

echo "$(date --utc -Ins) Running the test"
make ci-run
