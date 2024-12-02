#!/bin/bash

export RHDH_OPERATOR_NAMESPACE=rhdh-operator

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1090,SC1091
source "$(readlink -m "$SCRIPT_DIR/../../test.env")"

pushd "$SCRIPT_DIR/../rhdh-setup" || exit
./deploy.sh -o -d
popd || exit
