#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

echo -e "\n === Setting up RHDH scalability test ===\n"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1090,SC1091
source "$(readlink -m "$SCRIPT_DIR"/../../test.env)"
