#!/bin/bash

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1090,SC1091
source "$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$SCRIPT_DIR"/../../test.env)"

export RHDH_NAMESPACE=${RHDH_NAMESPACE:-rhdh-performance}
export RHDH_HELM_RELEASE_NAME=${RHDH_HELM_RELEASE_NAME:-rhdh}
export RHDH_INSTALL_METHOD=${RHDH_INSTALL_METHOD:-helm}

cli="oc"
clin="$cli -n $RHDH_NAMESPACE"

export RHDH_DB_HOST RHDH_DB_SECRET RHDH_DB_USERNAME
RHDH_DB_HOST="rhdh-postgresql-cluster-pgbouncer"

RHDH_DB_PASSWORD_SECRET="rhdh-db-credentials"
RHDH_DB_PASSWORD_KEY="POSTGRES_PASSWORD"
RHDH_DB_USERNAME_SECRET="rhdh-db-credentials"
RHDH_DB_USERNAME_KEY="POSTGRES_USER"

RHDH_DB_SONATAFLOW_PASSWORD_SECRET="rhdh-db-sonataflow-credentials"
RHDH_DB_SONATAFLOW_PASSWORD_KEY="POSTGRES_PASSWORD"
RHDH_DB_SONATAFLOW_USERNAME_SECRET="rhdh-db-sonataflow-credentials"
RHDH_DB_SONATAFLOW_USERNAME_KEY="POSTGRES_USER"

RHDH_DB_PASSWORD=$($clin get secret "$RHDH_DB_PASSWORD_SECRET" -o yaml | yq ".data.$RHDH_DB_PASSWORD_KEY" | base64 -d)
RHDH_DB_USERNAME=$($clin get secret "$RHDH_DB_USERNAME_SECRET" -o yaml | yq ".data.$RHDH_DB_USERNAME_KEY" | base64 -d)

if [ -n "$ENABLE_ORCHESTRATOR" ]; then
  RHDH_DB_SONATAFLOW_PASSWORD=$($clin get secret "$RHDH_DB_SONATAFLOW_PASSWORD_SECRET" -o yaml | yq ".data.$RHDH_DB_SONATAFLOW_PASSWORD_KEY" | base64 -d)
  RHDH_DB_SONATAFLOW_USERNAME=$($clin get secret "$RHDH_DB_SONATAFLOW_USERNAME_SECRET" -o yaml | yq ".data.$RHDH_DB_SONATAFLOW_USERNAME_KEY" | base64 -d)
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
  echo "  rhdh:     $RHDH_DB_USERNAME / $RHDH_DB_PASSWORD"
  if [ -n "$ENABLE_ORCHESTRATOR" ]; then
    echo "  sonataflow: $RHDH_DB_SONATAFLOW_USERNAME / $RHDH_DB_SONATAFLOW_PASSWORD"
  else
    echo "  sonataflow: not available (Orchestrator not enabled)"
  fi
  echo "  keycloak: keycloak / $($clin get secret keycloak-postgresql -o yaml | yq '.data.password' | base64 -d)"
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
