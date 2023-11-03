#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

export DOCKERIO_TOKEN SCENARIO

DOCKERIO_TOKEN=$(cat /usr/local/ci-secrets/backstage-performance/dockerio.token)

make ci-run
