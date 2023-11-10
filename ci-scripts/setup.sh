#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

echo "TODO: implement installation and setup of backstage to given openshift cluster"

export GITHUB_TOKEN QUAY_TOKEN KUBECONFIG

GITHUB_TOKEN=$(cat /usr/local/ci-secrets/backstage-performance/github.token)
QUAY_TOKEN=$(cat /usr/local/ci-secrets/backstage-performance/quay.token)


cd ./ci-scripts/rhdh-setup

./deploy.sh
