#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

echo "TODO: implement installation and setup of backstage to given openshift cluster"

export GITHUB_TOKEN QUAY_TOKEN KUBECONFIG

GITHUB_TOKEN=$(cat /usr/local/ci-secrets/backstage-performance/github.token)
QUAY_TOKEN=$(cat /usr/local/ci-secrets/backstage-performance/quay.token)

echo "$(date --utc -Ins) Creating namespace"
make namespace

cd ./ci-scripts/rhdh-setup

export RHDH_DEPLOYMENT_REPLICAS=10
export RHDH_DB_REPLICAS=5
export RHDH_KEYCLOAK_REPLICAS=5

echo "$(date --utc -Ins) Running deployment script"
./deploy.sh
