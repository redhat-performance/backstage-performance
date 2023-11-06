#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

export DOCKERIO_TOKEN SCENARIO

DOCKERIO_TOKEN=$(cat /usr/local/ci-secrets/backstage-performance/dockerio.token)

SCENARIO=oc-license-test
HOST="https://$(oc get route downloads -n openshift-console -o jsonpath='{.spec.host}')"

make ci-run
