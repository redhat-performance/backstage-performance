#!/bin/bash

export RHDH_OPERATOR_NAMESPACE=rhdh-operator

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1090,SC1091
source "$(readlink -m "$SCRIPT_DIR/../../test.env")"

cli="oc"

$cli delete namespace "$RHDH_OPERATOR_NAMESPACE" --ignore-not-found=true

envsubst <"$SCRIPT_DIR/operator.yaml" | $cli delete -f - --ignore-not-found=true
