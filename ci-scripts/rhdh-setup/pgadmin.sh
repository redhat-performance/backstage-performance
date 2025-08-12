#!/bin/bash

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1090,SC1091
source "$(readlink -f "$SCRIPT_DIR"/../../test.env)"

export RHDH_NAMESPACE=${RHDH_NAMESPACE:-rhdh-performance}
export RHDH_HELM_RELEASE_NAME=${RHDH_HELM_RELEASE_NAME:-rhdh}
export RHDH_INSTALL_METHOD=${RHDH_INSTALL_METHOD:-helm}

cli="oc"
clin="$cli -n $RHDH_NAMESPACE"

export RHDH_DB_HOST RHDH_DB_SECRET
if [ "$RHDH_INSTALL_METHOD" == "helm" ]; then
  RHDH_DB_HOST="${RHDH_HELM_RELEASE_NAME}-postgresql-primary"
  RHDH_DB_SECRET="${RHDH_HELM_RELEASE_NAME}-postgresql"
  RHDH_DB_SECRET_KEY=postgres-password
elif [ "$RHDH_INSTALL_METHOD" == "olm" ]; then
  RHDH_DB_HOST=backstage-psql-developer-hub
  RHDH_DB_SECRET=backstage-psql-secret-developer-hub
  RHDH_DB_SECRET_KEY=POSTGRES_PASSWORD
fi

uninstall() {
  $clin delete -f pgadmin.yaml --ignore-not-found=true
}

install() {
  envsubst <pgadmin.yaml | $clin apply -f -

  $clin rollout restart deployment/pgadmin
  $clin rollout status deployment/pgadmin -w

  echo
  echo "To access the pgAdmin console:"
  echo
  echo "  https://$($clin get route pgadmin -o json | jq -rc '.spec.host')"
  echo
  echo "NOTE: It takes some time to start the pgAdmin up. If you get 'Application is not available' try again in about 10 seconds."
  echo
  echo "For login use the following credentials:"
  echo "  Email:    admin@example.com"
  echo "  Password: admin"
  echo
  echo "For DB use corresponding password:"
  echo "  rhdh:     $($clin get secret "$RHDH_DB_SECRET" -o yaml | yq ".data.$RHDH_DB_SECRET_KEY" | base64 -d)"
  echo "  keycloak: $($clin get secret keycloak-db-secret -o yaml | yq '.data.POSTGRES_PASSWORD' | base64 -d)"
}

while getopts "di" flag; do
  case "${flag}" in
  d)
    uninstall
    ;;
  i)
    install
    ;;
  \?)
    log_warn "Invalid option: ${flag} - defaulting to -i (install)"
    install
    ;;
  esac
done
