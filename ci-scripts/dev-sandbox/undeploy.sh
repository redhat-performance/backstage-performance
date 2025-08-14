#!/bin/bash

export RHDH_OPERATOR_NAMESPACE=rhdh-operator

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1090,SC1091
source "$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$SCRIPT_DIR/../../test.env")"

pushd "$SCRIPT_DIR/../rhdh-setup" || exit
./deploy.sh -o -d
popd || exit
