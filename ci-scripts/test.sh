#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

export DOCKERIO_TOKEN SCENARIO

DOCKERIO_TOKEN=$(cat /usr/local/ci-secrets/backstage-performance/dockerio.token)

# testing env
#export USERS=1000
#export WORKERS=10
#export DURATION=10m
export SCENARIO="list-catalog"

export HOST="https://$(oc get routes rhdh-developer-hub -n rhdh-performance -o jsonpath='{.spec.host}')"
# end-of testing env

echo "$(date --utc -Ins) Running the test"
make clean ci-run
