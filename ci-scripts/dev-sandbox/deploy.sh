#!/bin/bash

export RHDH_OPERATOR_NAMESPACE=rhdh-operator

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1090,SC1091
source "$(readlink -m "$SCRIPT_DIR/../../test.env")"

rootdir=$(readlink -m "$SCRIPT_DIR/../..")

cli="oc"
clin="$cli -n $RHDH_OPERATOR_NAMESPACE"

$cli create namespace "$RHDH_OPERATOR_NAMESPACE" --dry-run=client -o yaml | $cli apply -f -

until envsubst <"$rootdir/ci-scripts/rhdh-setup/template/backstage/secret-rhdh-pull-secret.yaml" | $clin apply -f -; do $clin delete secret rhdh-pull-secret --ignore-not-found=true; done
envsubst <"$SCRIPT_DIR/operator.yaml" | $cli apply -f -
