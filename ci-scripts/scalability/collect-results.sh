#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

echo -e "\n === Collecting test results and metrics for RHDH scalability test ===\n"

ARTIFACT_DIR=$(readlink -m "${ARTIFACT_DIR:-.artifacts}")
mkdir -p "$ARTIFACT_DIR"
