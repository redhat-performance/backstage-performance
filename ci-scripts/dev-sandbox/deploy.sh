#!/bin/bash

export RHDH_OPERATOR_NAMESPACE=rhdh-operator

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1090,SC1091
source "$(readlink -m "$SCRIPT_DIR/../../test.env")"

rootdir=$(readlink -m "$SCRIPT_DIR/../..")

export TMP_DIR
TMP_DIR=$(readlink -m "${TMP_DIR:-"$rootdir/.tmp"}")
mkdir -p "${TMP_DIR}"

cli="oc"
clin="$cli -n $RHDH_OPERATOR_NAMESPACE"

$cli create namespace "$RHDH_OPERATOR_NAMESPACE" --dry-run=client -o yaml | $cli apply -f -

until envsubst <"$rootdir/ci-scripts/rhdh-setup/template/backstage/secret-rhdh-pull-secret.yaml" | $clin apply -f -; do $clin delete secret rhdh-pull-secret --ignore-not-found=true; done
pushd "$rootdir/ci-scripts/rhdh-setup" || exit
OLM_CHANNEL="${RHDH_OLM_CHANNEL}" UPSTREAM_IIB="${RHDH_OLM_INDEX_IMAGE}" NAMESPACE_SUBSCRIPTION="${RHDH_OPERATOR_NAMESPACE}" WATCH_EXT_CONF="${RHDH_OLM_WATCH_EXT_CONF}" ./install-rhdh-catalog-source.sh --install-operator "${RHDH_OLM_OPERATOR_PACKAGE:-rhdh}"
popd || exit
