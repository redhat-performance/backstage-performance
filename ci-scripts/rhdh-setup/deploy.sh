#!/bin/bash
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1090,SC1091
source "$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$SCRIPT_DIR"/../../test.env)"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/create_resource.sh"

[ -n "${QUAY_TOKEN}" ]
[ -n "${GITHUB_TOKEN}" ]
[ -n "${GITHUB_USER}" ]
[ -n "${GITHUB_REPO}" ]

export RHDH_NAMESPACE=${RHDH_NAMESPACE:-rhdh-performance}
export RHDH_HELM_RELEASE_NAME=${RHDH_HELM_RELEASE_NAME:-rhdh}

export RHDH_OPERATOR_NAMESPACE=${RHDH_OPERATOR_NAMESPACE:-rhdh-operator}

cli="oc"
clin="$cli -n $RHDH_NAMESPACE"

export RHDH_DEPLOYMENT_REPLICAS=${RHDH_DEPLOYMENT_REPLICAS:-1}
export RHDH_DB_REPLICAS=${RHDH_DB_REPLICAS:-1}
export RHDH_DB_STORAGE=${RHDH_DB_STORAGE:-1Gi}
export RHDH_RESOURCES_CPU_REQUESTS=${RHDH_RESOURCES_CPU_REQUESTS:-}
export RHDH_RESOURCES_CPU_LIMITS=${RHDH_RESOURCES_CPU_LIMITS:-}
export RHDH_RESOURCES_MEMORY_REQUESTS=${RHDH_RESOURCES_MEMORY_REQUESTS:-}
export RHDH_RESOURCES_MEMORY_LIMITS=${RHDH_RESOURCES_MEMORY_LIMITS:-}
export RHDH_DB_RESOURCES_CPU_REQUESTS=${RHDH_DB_RESOURCES_CPU_REQUESTS:-}
export RHDH_DB_RESOURCES_CPU_LIMITS=${RHDH_DB_RESOURCES_CPU_LIMITS:-}
export RHDH_DB_RESOURCES_MEMORY_REQUESTS=${RHDH_DB_RESOURCES_MEMORY_REQUESTS:-}
export RHDH_DB_RESOURCES_MEMORY_LIMITS=${RHDH_DB_RESOURCES_MEMORY_LIMITS:-}
export RHDH_KEYCLOAK_REPLICAS=${RHDH_KEYCLOAK_REPLICAS:-1}

export RHDH_IMAGE_REGISTRY=${RHDH_IMAGE_REGISTRY:-}
export RHDH_IMAGE_REPO=${RHDH_IMAGE_REPO:-}
export RHDH_IMAGE_TAG=${RHDH_IMAGE_TAG:-}

export RHDH_BASE_VERSION=${RHDH_BASE_VERSION:-1.9}

export RHDH_HELM_REPO=${RHDH_HELM_REPO:-oci://quay.io/rhdh/chart}
export RHDH_HELM_CHART=${RHDH_HELM_CHART:-redhat-developer-hub}
export RHDH_HELM_CHART_VERSION=${RHDH_HELM_CHART_VERSION:-$(skopeo list-tags docker://quay.io/rhdh/chart | jq -rc '.Tags[]' | grep "${RHDH_BASE_VERSION//./\\.}"'-.*' | sort -V | tail -n1)}

export RHDH_HELM_ORCHESTRATOR_REPO=${RHDH_HELM_ORCHESTRATOR_REPO:-oci://quay.io/rhdh/orchestrator-infra-chart}
export RHDH_HELM_ORCHESTRATOR_CHART=${RHDH_HELM_ORCHESTRATOR_CHART:-redhat-developer-hub-orchestrator-infra}
export RHDH_HELM_ORCHESTRATOR_CHART_VERSION=${RHDH_HELM_ORCHESTRATOR_CHART_VERSION:-${RHDH_HELM_CHART_VERSION}}

OCP_VER="$(oc version -o json | jq -r '.openshiftVersion' | sed -r -e "s#([0-9]+\.[0-9]+)\..+#\1#")"
export RHDH_OLM_INDEX_IMAGE="${RHDH_OLM_INDEX_IMAGE:-quay.io/rhdh/iib:${RHDH_BASE_VERSION}-v${OCP_VER}-x86_64}"
export RHDH_OLM_CHANNEL=${RHDH_OLM_CHANNEL:-fast}
export RHDH_OLM_OPERATOR_PACKAGE=${RHDH_OLM_OPERATOR_PACKAGE:-rhdh}
export RHDH_OLM_WATCH_EXT_CONF=${RHDH_OLM_WATCH_EXT_CONF:-true}
export RHDH_OLM_OPERATOR_RESOURCES_CPU_REQUESTS=${RHDH_OLM_OPERATOR_RESOURCES_CPU_REQUESTS:-}
export RHDH_OLM_OPERATOR_RESOURCES_CPU_LIMITS=${RHDH_OLM_OPERATOR_RESOURCES_CPU_LIMITS:-}
export RHDH_OLM_OPERATOR_RESOURCES_MEMORY_REQUESTS=${RHDH_OLM_OPERATOR_RESOURCES_MEMORY_REQUESTS:-}
export RHDH_OLM_OPERATOR_RESOURCES_MEMORY_LIMITS=${RHDH_OLM_OPERATOR_RESOURCES_MEMORY_LIMITS:-}
export RHDH_OLM_OPERATOR_RESOURCES_EPHEMERAL_STORAGE_REQUESTS=${RHDH_OLM_OPERATOR_RESOURCES_EPHEMERAL_STORAGE_REQUESTS:-}

export PRE_LOAD_DB="${PRE_LOAD_DB:-true}"
export BACKSTAGE_USER_COUNT="${BACKSTAGE_USER_COUNT:-1}"
export GROUP_COUNT="${GROUP_COUNT:-1}"
export API_COUNT="${API_COUNT:-1}"
export COMPONENT_COUNT="${COMPONENT_COUNT:-1}"
export KEYCLOAK_USER_PASS=${KEYCLOAK_USER_PASS:-$(mktemp -u XXXXXXXXXX)}
export AUTH_PROVIDER="${AUTH_PROVIDER:-''}"
export ENABLE_RBAC="${ENABLE_RBAC:-false}"
export ENABLE_ORCHESTRATOR="${ENABLE_ORCHESTRATOR:-false}"
export FORCE_ORCHESTRATOR_INFRA_UNINSTALL="${FORCE_ORCHESTRATOR_INFRA_UNINSTALL:-false}"
export ENABLE_PROFILING="${ENABLE_PROFILING:-false}"
export RBAC_POLICY="${RBAC_POLICY:-all_groups_admin}"
export RBAC_POLICY_FILE_URL="${RBAC_POLICY_FILE_URL:-}"
export RBAC_POLICY_PVC_STORAGE="${RBAC_POLICY_PVC_STORAGE:-100Mi}"
export RBAC_POLICY_UPLOAD_TO_GITHUB="${RBAC_POLICY_UPLOAD_TO_GITHUB:-true}"
export RHDH_LOG_LEVEL="${RHDH_LOG_LEVEL:-warn}"
export KEYCLOAK_LOG_LEVEL="${KEYCLOAK_LOG_LEVEL:-WARN}"

export PSQL_LOG="${PSQL_LOG:-true}"
export RHDH_METRIC="${RHDH_METRIC:-true}"
export PSQL_EXPORT="${PSQL_EXPORT:-false}"
export ENABLE_PGBOUNCER="${ENABLE_PGBOUNCER:-false}"
export PGBOUNCER_REPLICAS="${PGBOUNCER_REPLICAS:-0}"
export LOG_MIN_DURATION_STATEMENT="${LOG_MIN_DURATION_STATEMENT:-65}"
export LOG_MIN_DURATION_SAMPLE="${LOG_MIN_DURATION_SAMPLE:-50}"
export LOG_STATEMENT_SAMPLE_RATE="${LOG_STATEMENT_SAMPLE_RATE:-0.7}"

export INSTALL_METHOD=helm

TMP_DIR=$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "${TMP_DIR:-.tmp}")
mkdir -p "${TMP_DIR}"

###############################################################################
# Section 1: Namespace and Operator Setup
###############################################################################

setup_rhdh_namespace() {
    log_info "Setting up RHDH namespace"
    if ! $cli get namespace "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
        $cli create namespace "${RHDH_NAMESPACE}"
    else
        log_info "RHDH namespace already exists, skipping..."
    fi
}

setup_operator_group() {
    if $clin get operatorgroup -o name 2>/dev/null | grep -q .; then
        log_info "OperatorGroup already exists in $RHDH_NAMESPACE namespace, skipping..."
    else
        log_info "Creating OperatorGroup in $RHDH_NAMESPACE namespace"
        envsubst <template/backstage/operator-group.yaml | $clin apply -f -
    fi
}

###############################################################################
# Section 2: Orchestrator Infrastructure
###############################################################################

is_orchestrator_infra_installed() {
    helm list -n "${RHDH_NAMESPACE}" -q | grep -q "^${RHDH_HELM_RELEASE_NAME}-orchestrator-infra$"
    return $?
}

is_serverless_operator_installed() {
    namespace=$1
    # Check if namespace exists first
    if ! $cli get namespace "$namespace" >/dev/null 2>&1; then
        return 1
    fi
    # Check for subscriptions or CSVs
    $cli get subscription -n "$namespace" -o name 2>/dev/null | grep -qE "serverless-operator|logic-operator" ||
        $cli get csv -n "$namespace" -o name 2>/dev/null | grep -qE "serverless|logic-operator"
    return $?
}

install_orchestrator_infra() {
    if is_orchestrator_infra_installed || is_serverless_operator_installed openshift-serverless || is_serverless_operator_installed openshift-serverless-logic; then
        log_info "Orchestrator infra is already installed, skipping installation"
        return 0
    fi

    orchestrator_version_arg=""
    orchestrator_chart_origin="$RHDH_HELM_ORCHESTRATOR_REPO"
    if [ -n "${RHDH_HELM_ORCHESTRATOR_CHART_VERSION}" ]; then
        orchestrator_version_arg="--version $RHDH_HELM_ORCHESTRATOR_CHART_VERSION"
        orchestrator_chart_origin="$orchestrator_chart_origin@$RHDH_HELM_ORCHESTRATOR_CHART_VERSION"
    fi
    log_info "Installing RHDH Orchestrator infra from $orchestrator_chart_origin"
    # shellcheck disable=SC2086
    helm upgrade "${RHDH_HELM_RELEASE_NAME}-orchestrator-infra" -i "${RHDH_HELM_ORCHESTRATOR_REPO}" ${orchestrator_version_arg} -n "${RHDH_NAMESPACE}"

    wait_and_approve_install_plans openshift-serverless
    wait_and_approve_install_plans openshift-serverless-logic
}

delete_orchestrator_infra() {
    log_info "Deleting RHDH Orchestrator infra"
    helm uninstall "${RHDH_HELM_RELEASE_NAME}-orchestrator-infra" --namespace "${RHDH_NAMESPACE}" --ignore-not-found=true --wait

    # Delete KnativeEventing custom resources first
    log_info "Deleting KnativeEventing custom resources"
    for ns in knative-eventing openshift-serverless; do
        if $cli get ns "$ns" >/dev/null 2>&1; then
            for res in $($cli get knativeeventings.operator.knative.dev -n "$ns" -o name 2>/dev/null); do
                log_info "Removing finalizers from $res in namespace $ns"
                $cli patch "$res" -n "$ns" -p '{"metadata":{"finalizers":[]}}' --type=merge
                $cli delete "$res" -n "$ns" --ignore-not-found=true --wait
            done
        fi
    done

    # Delete KnativeServing custom resources
    log_info "Deleting KnativeServing custom resources"
    for ns in knative-serving openshift-serverless; do
        if $cli get ns "$ns" >/dev/null 2>&1; then
            for res in $($cli get knativeservings.operator.knative.dev -n "$ns" -o name 2>/dev/null); do
                log_info "Removing finalizers from $res in namespace $ns"
                $cli patch "$res" -n "$ns" -p '{"metadata":{"finalizers":[]}}' --type=merge
                $cli delete "$res" -n "$ns" --ignore-not-found=true --wait
            done
        fi
    done

    # Delete subscriptions
    $cli delete subscription.operators.coreos.com serverless-operator -n openshift-serverless --ignore-not-found=true --wait
    $cli delete subscription.operators.coreos.com logic-operator-rhel8 -n openshift-serverless-logic --ignore-not-found=true --wait

    # Delete CSVs (ClusterServiceVersions) to remove operators
    log_info "Deleting ClusterServiceVersions for Knative operators"
    for ns in openshift-serverless openshift-serverless-logic knative-eventing knative-serving; do
        if $cli get ns "$ns" >/dev/null 2>&1; then
            for csv in $($cli get csv -n "$ns" -o name 2>/dev/null | grep -E 'serverless|knative|logic-operator'); do
                $cli delete "$csv" -n "$ns" --ignore-not-found=true --wait
            done
        fi
    done

    # Remove Knative webhook configurations to prevent validation errors during cleanup
    log_info "Removing Knative webhook configurations"
    $cli delete validatingwebhookconfiguration config.webhook.serving.knative.dev --ignore-not-found=true --wait
    $cli delete validatingwebhookconfiguration validation.webhook.serving.knative.dev --ignore-not-found=true --wait
    $cli delete validatingwebhookconfiguration validation.webhook.eventing.knative.dev --ignore-not-found=true --wait
    $cli delete mutatingwebhookconfiguration webhook.serving.knative.dev --ignore-not-found=true --wait
    $cli delete mutatingwebhookconfiguration webhook.eventing.knative.dev --ignore-not-found=true --wait

    # Force delete any remaining pods in Knative namespaces
    log_info "Force deleting remaining pods in Knative namespaces"
    for ns in knative-eventing knative-eventing-ingress knative-serving knative-serving-ingress openshift-serverless openshift-serverless-logic; do
        if $cli get ns "$ns" >/dev/null 2>&1; then
            for pod in $($cli get pods -n "$ns" -o name 2>/dev/null); do
                $cli delete "$pod" -n "$ns" --force --grace-period=0 --ignore-not-found=true --wait
            done
        fi
    done

    # Now delete the namespaces
    log_info "Deleting Knative and Serverless namespaces"
    $cli delete ns openshift-serverless --ignore-not-found=true --wait
    $cli delete ns openshift-serverless-logic --ignore-not-found=true --wait
    $cli delete ns knative-eventing --ignore-not-found=true --wait
    $cli delete ns knative-eventing-ingress --ignore-not-found=true --wait
    $cli delete ns knative-serving --ignore-not-found=true --wait
    $cli delete ns knative-serving-ingress --ignore-not-found=true --wait
}

install_workflows() {
    export POSTGRES_HOST POSTGRES_PORT SONATAFLOW_DB_SECRET
    if [[ "${ENABLE_PGBOUNCER}" == "true" && "${PGBOUNCER_REPLICAS}" -gt 0 ]]; then
        SONATAFLOW_DB_SECRET="rhdh-db-sonataflow-credentials"
    else
        SONATAFLOW_DB_SECRET="rhdh-db-credentials"
    fi
    POSTGRES_HOST="$($clin get secret "$SONATAFLOW_DB_SECRET" -o json | jq -r '.data.POSTGRES_HOST' | base64 -d)"
    POSTGRES_PORT="$($clin get secret "$SONATAFLOW_DB_SECRET" -o json | jq -r '.data.POSTGRES_PORT' | base64 -d)"
    log_info "Installing Orchestrator workflows"
    mkdir -p "$TMP_DIR/workflows"
    while IFS= read -r -d '' i; do
        # shellcheck disable=SC2094
        envsubst <"$i" >"$TMP_DIR/workflows/$(basename "$i")"
        $clin apply -f "$TMP_DIR/workflows/$(basename "$i")"
    done < <(find template/workflows/basic -type f -print0)
}

patch_sonataflow_flyway() {
    # Patch SonataFlowPlatform CR to use separate Flyway schema history tables
    # This prevents conflicts when data-index-service and jobs-service share the same database
    log_info "Patching SonataFlowPlatform CR for Flyway compatibility"

    # Patch dataIndex service with Flyway env vars
    log_info "Adding Flyway env vars to dataIndex service"
    $clin patch sonataflowplatform sonataflow-platform --type='merge' -p='{
        "spec": {
            "services": {
                "dataIndex": {
                    "podTemplate": {
                        "container": {
                            "env": [
                                {"name": "QUARKUS_FLYWAY_TABLE", "value": "flyway_schema_history_data_index"},
                                {"name": "QUARKUS_FLYWAY_SCHEMAS", "value": "data-index-service"},
                                {"name": "QUARKUS_FLYWAY_BASELINE_ON_MIGRATE", "value": "true"}
                            ]
                        }
                    }
                },
                "jobService": {
                    "podTemplate": {
                        "container": {
                            "env": [
                                {"name": "QUARKUS_FLYWAY_TABLE", "value": "flyway_schema_history_jobs"}
                            ]
                        }
                    }
                }
            }
        }
    }'

    log_info "Waiting for SonataFlow deployments to be ready"
    wait_to_start deployment "sonataflow-platform-data-index-service" 300 300
    wait_to_start deployment "sonataflow-platform-jobs-service" 300 300
}

uninstall_workflows() {
    log_info "Uninstalling Orchestrator workflows"
    $clin delete -f template/workflows/basic --ignore-not-found=true || true
}

###############################################################################
# Section 3: Keycloak Authentication
###############################################################################

assign_roles_to_client() {
    ADMIN_TOKEN=$(get_token "keycloak")
    SA_USER_ID=$(curl -s -k "$(keycloak_url)/admin/realms/backstage/users?username=service-account-backstage" -H "Authorization: Bearer $ADMIN_TOKEN" | jq -r '.[0].id')
    REALM_MGMT_ID=$(curl -s -k "$(keycloak_url)/admin/realms/backstage/clients?clientId=realm-management" -H "Authorization: Bearer $ADMIN_TOKEN" | jq -r '.[0].id')

    ROLE_NAMES=$(curl -s -k "$(keycloak_url)/admin/realms/backstage/clients/$REALM_MGMT_ID/roles" -H "Authorization: Bearer $ADMIN_TOKEN" | jq -r '.[].name')

    while IFS= read -r role_name; do
        [ -z "$role_name" ] && continue

        ROLE_JSON=$(curl -s -k "$(keycloak_url)/admin/realms/backstage/clients/$REALM_MGMT_ID/roles/$role_name" \
            -H "Authorization: Bearer $ADMIN_TOKEN")

        curl -s -k -X POST \
            "$(keycloak_url)/admin/realms/backstage/users/$SA_USER_ID/role-mappings/clients/$REALM_MGMT_ID" \
            -H "Authorization: Bearer $ADMIN_TOKEN" \
            -H "Content-Type: application/json" \
            -d "[$ROLE_JSON]"
    done <<<"$ROLE_NAMES"
}

keycloak_install() {
    export KEYCLOAK_CLIENT_SECRET
    export COOKIE_SECRET
    KEYCLOAK_CLIENT_SECRET=$(mktemp -u XXXXXXXXXX)
    COOKIE_SECRET=$(
        dd if=/dev/urandom bs=32 count=1 2>/dev/null | base64 | tr -d -- '\n' | tr -- '+/' '-_'
        echo
    )
    envsubst <template/keycloak/keycloak-op.yaml | $clin apply -f -
    envsubst <template/backstage/perf-test-secrets.yaml | $clin apply -f -
    grep -m 1 "rhbk-operator" <($clin get pods -w)
    wait_to_start deployment rhbk-operator 300 300

    export KEYCLOAK_DB_PASSWORD
    KEYCLOAK_DB_PASSWORD=$(mktemp -u XXXXXXXXXX)
    export KEYCLOAK_DB_STORAGE
    KEYCLOAK_DB_STORAGE=${KEYCLOAK_DB_STORAGE:-${RHDH_DB_STORAGE:-1Gi}}

    log_info "Creating Keycloak PostgreSQL database with storage: $KEYCLOAK_DB_STORAGE"
    envsubst <template/keycloak/keycloak-postgresql.yaml | $clin apply -f -
    wait_to_start statefulset keycloak-postgresql 300 300

    $clin create secret generic keycloak-db-user --from-literal=keycloak-db-user=keycloak --dry-run=client -o yaml | $clin apply -f -

    envsubst <template/keycloak/keycloak.yaml | $clin apply -f -
    wait_to_start statefulset rhdh-keycloak 450 600

    $clin create route edge keycloak \
        --service=rhdh-keycloak-service \
        --port=8080 \
        --dry-run=client -o yaml | $clin apply -f -

    if [ "$INSTALL_METHOD" == "helm" ]; then
        export OAUTH2_REDIRECT_URI="https://${RHDH_HELM_RELEASE_NAME}-developer-hub-${RHDH_NAMESPACE}.${OPENSHIFT_APP_DOMAIN}/oauth2/callback"
    elif [ "$INSTALL_METHOD" == "olm" ]; then
        if [ "$AUTH_PROVIDER" == "keycloak" ]; then
            export OAUTH2_REDIRECT_URI="https://rhdh-${RHDH_NAMESPACE}.${OPENSHIFT_APP_DOMAIN}/oauth2/callback"
        else
            export OAUTH2_REDIRECT_URI="https://backstage-developer-hub-${RHDH_NAMESPACE}.${OPENSHIFT_APP_DOMAIN}/oauth2/callback"
        fi
    fi
    # shellcheck disable=SC2016
    envsubst '${KEYCLOAK_CLIENT_SECRET} ${OAUTH2_REDIRECT_URI} ${KEYCLOAK_USER_PASS}' <template/keycloak/keycloakRealmImport.yaml | $clin apply -f -
    $clin create secret generic keycloak-client-secret-backstage --from-literal=CLIENT_ID=backstage --from-literal=CLIENT_SECRET="$KEYCLOAK_CLIENT_SECRET" --dry-run=client -o yaml | oc apply -f -
    # Wait up to 1 minute for completion realm generation
    $clin wait --for=condition=Done keycloakrealmimport/backstage-realm-import --timeout=60s
    assign_roles_to_client
}

###############################################################################
# Section 4: Catalog Population
###############################################################################

create_users_groups() {
    date -u -Ins >"${TMP_DIR}/populate-users-groups-before"
    create_groups
    create_users
    date -u -Ins >"${TMP_DIR}/populate-users-groups-after"
}

create_objs() {
    if [[ ${GITHUB_USER} ]] && [[ ${GITHUB_REPO} ]]; then
        date -u -Ins >"${TMP_DIR}/populate-catalog-before"
        create_per_grp create_cmp COMPONENT_COUNT
        create_per_grp create_api API_COUNT
        date -u -Ins >"${TMP_DIR}/populate-catalog-after"
    else
        log_warn "skipping component creating. GITHUB_REPO and GITHUB_USER not set"
        exit 1
    fi
}

get_catalog_entity_count() {
    entity_type=$1
    ACCESS_TOKEN=$(get_token "rhdh")
    curl -s -k "$(backstage_url)/api/catalog/entities/by-query?limit=0&filter=kind%3D${entity_type}" --cookie "$COOKIE" --cookie-jar "$COOKIE" -H 'Content-Type: application/json' -H 'Authorization: Bearer '"$ACCESS_TOKEN" | tee -a "$TMP_DIR/get_$(echo "$entity_type" | tr '[:upper:]' '[:lower:]')_count.log" | jq -r '.totalItems'
}

###############################################################################
# Section 5: Database
###############################################################################

wait_for_rhdh_db_to_start() {
    wait_to_exist "$RHDH_NAMESPACE" "statefulset" "rhdh-postgresql-cluster-primary" 300
    $clin wait --for=condition=Ready pod -l postgres-operator.crunchydata.com/instance-set=primary --timeout=300s
    if [[ "${ENABLE_PGBOUNCER}" == "true" && "${PGBOUNCER_REPLICAS}" -gt 0 ]]; then
        wait_to_start deployment "rhdh-postgresql-cluster-pgbouncer" 300 300
    fi
}

setup_rhdh_db() {
    log_info "Setting up RHDH database"
    setup_rhdh_namespace
    setup_operator_group
    envsubst <template/backstage/rhdh-db/crunchy-postgres-op.yaml | $clin apply -f -
    wait_to_start deployment pgo 300 300
    export RHDH_DB_MAX_CONNECTIONS PGBOUNCER_MAX_CLIENT_CONNECTIONS PGBOUNCER_DEFAULT_POOL_SIZE PGBOUNCER_MAX_DB_CONNECTIONS PGBOUNCER_MAX_USER_CONNECTIONS

    # PgBouncer is optional: disabled when ENABLE_PGBOUNCER is false or PGBOUNCER_REPLICAS is 0
    if [[ "${ENABLE_PGBOUNCER}" != "true" || "${PGBOUNCER_REPLICAS}" -eq 0 ]]; then
        log_info "PgBouncer disabled (ENABLE_PGBOUNCER=${ENABLE_PGBOUNCER}, PGBOUNCER_REPLICAS=${PGBOUNCER_REPLICAS}); using primary instance directly"
        PGBOUNCER_REPLICAS=0
        PGBOUNCER_MAX_CLIENT_CONNECTIONS=1
        PGBOUNCER_DEFAULT_POOL_SIZE=1
        PGBOUNCER_MAX_DB_CONNECTIONS=1
        PGBOUNCER_MAX_USER_CONNECTIONS=1
        CLIENT_CONNECTIONS_PER_RHDH_INSTANCE=50
        DB_CONNECTIONS_HEADROOM_PER_RHDH_INSTANCE=5
        MIN_RHDH_DB_MAX_CONNECTIONS=150
        _rhdh_db_max_conn=$(bc <<<"$RHDH_DEPLOYMENT_REPLICAS * ($CLIENT_CONNECTIONS_PER_RHDH_INSTANCE + $DB_CONNECTIONS_HEADROOM_PER_RHDH_INSTANCE)")
        RHDH_DB_MAX_CONNECTIONS=$(bc <<<"if ($_rhdh_db_max_conn < $MIN_RHDH_DB_MAX_CONNECTIONS) $MIN_RHDH_DB_MAX_CONNECTIONS else $_rhdh_db_max_conn")
    else
        # Connection sizing parameters (PgBouncer enabled)
        CLIENT_CONNECTIONS_PER_RHDH_INSTANCE=50     # Expected DB connections per RHDH replica
        DB_CONNECTIONS_HEADROOM_PER_RHDH_INSTANCE=5 # Extra headroom per RHDH replica
        DB_CONNECTIONS_ADMIN_HEADROOM=20            # Reserved for admin/monitoring connections
        RHDH_DATABASE_COUNT=30                      # Approximate number of RHDH plugin databases (~20 current + ~10 future)

        # Minimum values to handle Backstage startup burst (concurrent plugin initialization)
        # During startup, ~30 plugins create schemas concurrently regardless of replica count
        MIN_RHDH_DB_MAX_CONNECTIONS=150
        MIN_PGBOUNCER_MAX_CLIENT_CONNECTIONS=120
        MIN_PGBOUNCER_MAX_DB_CONNECTIONS=60
        # Pool size minimum equals database count to ensure each plugin can connect during startup burst
        MIN_PGBOUNCER_DEFAULT_POOL_SIZE=$RHDH_DATABASE_COUNT

        # Calculate based on replicas
        _rhdh_db_max_conn=$(bc <<<"$RHDH_DEPLOYMENT_REPLICAS * ($CLIENT_CONNECTIONS_PER_RHDH_INSTANCE + $DB_CONNECTIONS_HEADROOM_PER_RHDH_INSTANCE)")
        RHDH_DB_MAX_CONNECTIONS=$(bc <<<"if ($_rhdh_db_max_conn < $MIN_RHDH_DB_MAX_CONNECTIONS) $MIN_RHDH_DB_MAX_CONNECTIONS else $_rhdh_db_max_conn")

        # Each PgBouncer instance is sized to handle ALL client connections (for HA/failover)
        _pgb_max_client=$(bc <<<"scale=0; $RHDH_DEPLOYMENT_REPLICAS * $CLIENT_CONNECTIONS_PER_RHDH_INSTANCE" | sed 's,\..*,,')
        PGBOUNCER_MAX_CLIENT_CONNECTIONS=$(bc <<<"if ($_pgb_max_client < $MIN_PGBOUNCER_MAX_CLIENT_CONNECTIONS) $MIN_PGBOUNCER_MAX_CLIENT_CONNECTIONS else $_pgb_max_client")

        # Backend connections per PgBouncer instance - divided by PGBOUNCER_REPLICAS
        # to ensure total across all PgBouncer instances doesn't exceed the primary's max_connections.
        # Note: PgBouncer connects only to the primary instance; DB replicas are standby for HA failover.
        _pgb_max_db=$(bc <<<"scale=0; ($RHDH_DB_MAX_CONNECTIONS - $DB_CONNECTIONS_ADMIN_HEADROOM) / $PGBOUNCER_REPLICAS" | sed 's,\..*,,')
        PGBOUNCER_MAX_DB_CONNECTIONS=$(bc <<<"if ($_pgb_max_db < $MIN_PGBOUNCER_MAX_DB_CONNECTIONS) $MIN_PGBOUNCER_MAX_DB_CONNECTIONS else $_pgb_max_db")

        # Pool size per database - ensures all databases can use their share without exceeding max_db_connections
        _pgb_pool_size=$(bc <<<"scale=0; $PGBOUNCER_MAX_DB_CONNECTIONS / $RHDH_DATABASE_COUNT" | sed 's,\..*,,')
        PGBOUNCER_DEFAULT_POOL_SIZE=$(bc <<<"if ($_pgb_pool_size < $MIN_PGBOUNCER_DEFAULT_POOL_SIZE) $MIN_PGBOUNCER_DEFAULT_POOL_SIZE else $_pgb_pool_size")

        PGBOUNCER_MAX_USER_CONNECTIONS=$(bc <<<"scale=0; $PGBOUNCER_MAX_DB_CONNECTIONS * 1.2" | sed 's,\..*,,')

        # Note: With pool_mode=transaction, connections are quickly returned to the pool after each transaction.
        # This allows efficient sharing even when pool_size * databases > max_db_connections,
        # as long as concurrent transactions don't exceed the limit simultaneously.
        # The reserve_pool provides additional burst capacity for ~30 plugins (reserve_pool_size=10, reserve_pool_timeout=5s).

        log_info "Database connection sizing (RHDH_DEPLOYMENT_REPLICAS=$RHDH_DEPLOYMENT_REPLICAS, RHDH_DB_REPLICAS=$RHDH_DB_REPLICAS, PGBOUNCER_REPLICAS=$PGBOUNCER_REPLICAS): RHDH_DB_MAX_CONNECTIONS=$RHDH_DB_MAX_CONNECTIONS, PGBOUNCER_MAX_CLIENT_CONNECTIONS=$PGBOUNCER_MAX_CLIENT_CONNECTIONS, PGBOUNCER_MAX_DB_CONNECTIONS=$PGBOUNCER_MAX_DB_CONNECTIONS, PGBOUNCER_DEFAULT_POOL_SIZE=$PGBOUNCER_DEFAULT_POOL_SIZE, PGBOUNCER_MAX_USER_CONNECTIONS=$PGBOUNCER_MAX_USER_CONNECTIONS"
    fi

    export POSTGRES_USER POSTGRES_PASSWORD POSTGRES_DATABASE_NAME POSTGRES_HOST POSTGRES_PORT

    if [[ "${ENABLE_PGBOUNCER}" == "true" && "${PGBOUNCER_REPLICAS}" -gt 0 ]]; then
        POSTGRES_HOST="rhdh-postgresql-cluster-pgbouncer"
        POSTGRES_USER=rhdh
    else
        POSTGRES_HOST="rhdh-postgresql-cluster-primary"
        POSTGRES_USER="rhdh-postgresql-cluster"
    fi
    POSTGRES_DATABASE_NAME="${POSTGRES_USER}"
    POSTGRES_PORT=5432

    # Create ConfigMap with SQL to grant permissions to rhdh user on public schema
    # Required for PostgreSQL 15+ where public schema CREATE is not granted by default
    #$clin create configmap rhdh-db-init-sql --from-literal=init.sql="ALTER SCHEMA public OWNER TO ${POSTGRES_USER}; GRANT ALL ON SCHEMA public TO ${POSTGRES_USER};" --dry-run=client -o yaml | $clin apply -f -

    envsubst <template/backstage/rhdh-db/postgres-cluster.yaml >|"$TMP_DIR/postgres-cluster.yaml"

    # Build the patch for PostgresCluster CR to persist config across restarts
    if ${PSQL_LOG}; then
        log_info "Setting up PostgreSQL logging via PostgresCluster CR"
        yq -i '.spec.patroni.dynamicConfiguration.postgresql.parameters |= . + {"log_min_duration_statement": "'"${LOG_MIN_DURATION_STATEMENT}"'"}' "$TMP_DIR/postgres-cluster.yaml"
        yq -i '.spec.patroni.dynamicConfiguration.postgresql.parameters |= . + {"log_min_duration_sample": "'"${LOG_MIN_DURATION_SAMPLE}"'"}' "$TMP_DIR/postgres-cluster.yaml"
        yq -i '.spec.patroni.dynamicConfiguration.postgresql.parameters |= . + {"log_statement_sample_rate": "'"${LOG_STATEMENT_SAMPLE_RATE}"'"}' "$TMP_DIR/postgres-cluster.yaml"
    fi
    if ${PSQL_EXPORT}; then
        log_info "Setting up PostgreSQL tracking via PostgresCluster CR"
        yq -i '.spec.patroni.dynamicConfiguration.postgresql.parameters |= . + {"track_io_timing": "on"}' "$TMP_DIR/postgres-cluster.yaml"
        yq -i '.spec.patroni.dynamicConfiguration.postgresql.parameters |= . + {"track_wal_io_timing": "on"}' "$TMP_DIR/postgres-cluster.yaml"
        yq -i '.spec.patroni.dynamicConfiguration.postgresql.parameters |= . + {"track_functions": "all"}' "$TMP_DIR/postgres-cluster.yaml"
        yq -i '.spec.patroni.dynamicConfiguration.postgresql.parameters |= . + {"stats_fetch_consistency": "cache"}' "$TMP_DIR/postgres-cluster.yaml"
        yq -i '.spec.patroni.dynamicConfiguration.postgresql.parameters |= . + {"shared_preload_libraries": "pgaudit,auto_explain,pg_stat_statements"}' "$TMP_DIR/postgres-cluster.yaml"
    fi

    if [[ "${ENABLE_PGBOUNCER}" == "true" && "${PGBOUNCER_REPLICAS}" -gt 0 ]]; then
        yq -i '.spec.users |= . + [{"name": "'"$POSTGRES_USER"'", "databases": ["'"$POSTGRES_DATABASE_NAME"'"], "options": "NOSUPERUSER CREATEDB"}]' "$TMP_DIR/postgres-cluster.yaml"
        yq -i '.spec.users |= . + [{"name": "sonataflow", "databases": [], "options": "NOSUPERUSER CREATEDB"}]' "$TMP_DIR/postgres-cluster.yaml"
    else
        yq -i '.spec.users |= . + [{"name": "'"$POSTGRES_USER"'", "databases": ["'"$POSTGRES_DATABASE_NAME"'"], "options": "SUPERUSER"}]' "$TMP_DIR/postgres-cluster.yaml"
    fi

    $clin apply -f "$TMP_DIR/postgres-cluster.yaml"
    wait_for_rhdh_db_to_start

    POSTGRES_PASSWORD=$($clin get secret "rhdh-postgresql-cluster-pguser-$POSTGRES_USER" -o jsonpath='{.data.password}' | base64 -d)

    $clin create secret generic rhdh-db-credentials --from-literal=POSTGRES_USER="$POSTGRES_USER" --from-literal=POSTGRES_PASSWORD="$POSTGRES_PASSWORD" --from-literal=POSTGRES_DATABASE_NAME="$POSTGRES_DATABASE_NAME" --from-literal=POSTGRES_HOST="$POSTGRES_HOST" --from-literal=POSTGRES_PORT="$POSTGRES_PORT" --dry-run=client -o yaml | $clin apply -f -

    if ${ENABLE_ORCHESTRATOR}; then
        POSTGRES_SONATAFLOW_PASSWORD=$($clin get secret "rhdh-postgresql-cluster-pguser-sonataflow" -o jsonpath='{.data.password}' | base64 -d)
        $clin create secret generic rhdh-db-sonataflow-credentials --from-literal=POSTGRES_USER="sonataflow" --from-literal=POSTGRES_PASSWORD="$POSTGRES_SONATAFLOW_PASSWORD" --from-literal=POSTGRES_DATABASE_NAME="sonataflow" --from-literal=POSTGRES_HOST="$POSTGRES_HOST" --from-literal=POSTGRES_PORT="$POSTGRES_PORT" --dry-run=client -o yaml | $clin apply -f -
    fi
}

delete_rhdh_db() {
    log_info "Deleting RHDH database"
    $clin delete -f template/backstage/rhdh-db/postgres-cluster.yaml --ignore-not-found=true --wait
    $clin delete -f template/backstage/rhdh-db/crunchy-postgres-op.yaml --ignore-not-found=true --wait
    $clin delete secret rhdh-db-credentials --ignore-not-found=true --wait
    $clin delete configmap rhdh-db-init-sql --ignore-not-found=true --wait
    $clin delete statefulset rhdh-postgresql-cluster-primary --ignore-not-found=true --wait
    $clin delete deployment rhdh-postgresql-cluster-pgbouncer --ignore-not-found=true --wait
}

plugins=("backstage_plugin_permission" "backstage_plugin_auth" "backstage_plugin_catalog" "backstage_plugin_scaffolder" "backstage_plugin_search" "backstage_plugin_app")

psql_debug_cleanup() {
    log_info "Removing PostgreSQL debug"
    helm uninstall pg-exporter -n "${RHDH_NAMESPACE}" --ignore-not-found=true --wait
    for plugin in "${plugins[@]}"; do
        helm uninstall "${plugin//_/-}" -n "${RHDH_NAMESPACE}" --ignore-not-found=true --wait
    done
}

# shellcheck disable=SC2016,SC1001,SC2086
psql_debug() {
    if ${PSQL_EXPORT}; then
        log_info "Debugging PostgreSQL"
        wait_to_exist "$RHDH_NAMESPACE" "statefulset" "rhdh-postgresql-cluster-primary" 300
        psql_db_ss=$($clin get statefulset -o name | grep rhdh-postgresql-cluster-primary | sed 's/statefulset.apps\///')
        psql_db_pod="${psql_db_ss}-0"
        log_info "Setting up PostgreSQL metrics exporter"
        $clin exec "${psql_db_pod}" -- sh -c 'psql -c "CREATE EXTENSION pg_stat_statements;"'

        helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
        export POSTGRES_HOST POSTGRES_PORT POSTGRES_USER POSTGRES_PASSWORD POSTGRES_DATABASE_NAME POSTGRES_EXPORTER_UID
        POSTGRES_HOST=rhdh-postgresql-cluster-primary
        POSTGRES_PORT=$($clin get secret "rhdh-db-credentials" -o jsonpath='{.data.POSTGRES_PORT}' | base64 -d)
        POSTGRES_USER=$($clin get secret "rhdh-db-credentials" -o jsonpath='{.data.POSTGRES_USER}' | base64 -d)
        POSTGRES_PASSWORD=$($clin get secret "rhdh-db-credentials" -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)
        POSTGRES_DATABASE_NAME=$($clin get secret "rhdh-db-credentials" -o jsonpath='{.data.POSTGRES_DATABASE_NAME}' | base64 -d)
        POSTGRES_EXPORTER_UID=$(oc get namespace "${RHDH_NAMESPACE}" -o go-template='{{ index .metadata.annotations "openshift.io/sa.scc.supplemental-groups" }}' | cut -d '/' -f 1)
        envsubst '${POSTGRES_HOST} ${POSTGRES_PORT} ${POSTGRES_USER} ${POSTGRES_PASSWORD} ${POSTGRES_EXPORTER_UID}' <template/postgres-exporter/chart-values.yaml >"$TMP_DIR/pg-exporter.yaml"
        helm install pg-exporter prometheus-community/prometheus-postgres-exporter -n "${RHDH_NAMESPACE}" -f "$TMP_DIR/pg-exporter.yaml"
        for plugin in "${plugins[@]}"; do
            export POSTGRES_DATABASE_NAME=$plugin
            envsubst '${POSTGRES_HOST} ${POSTGRES_PORT} ${POSTGRES_USER} ${POSTGRES_PASSWORD} ${POSTGRES_DATABASE_NAME} ${POSTGRES_EXPORTER_UID}' <template/postgres-exporter/values-template.yaml >"${TMP_DIR}/${plugin}.yaml"
            helm_name=${plugin//_/-}
            helm install "${helm_name}" prometheus-community/prometheus-postgres-exporter -n "${RHDH_NAMESPACE}" -f "${TMP_DIR}/${plugin}.yaml"
        done

        log_info "Setting up PostgreSQL monitoring"
        plugins=("pg-exporter" "backstage-plugin-permission" "backstage-plugin-auth" "backstage-plugin-catalog" "backstage-plugin-scaffolder" "backstage-plugin-search" "backstage-plugin-app")
        for plugin in "${plugins[@]}"; do
            export PG_LABEL=$plugin
            envsubst '${PG_LABEL} ${RHDH_NAMESPACE}' <template/postgres-exporter/service-monitor-template.yaml >"${TMP_DIR}/${plugin}-monitor.yaml"
            $clin apply -f "${TMP_DIR}/${plugin}-monitor.yaml"
        done
    fi
}

###############################################################################
# Section 6: RHDH Deployment
###############################################################################

setup_rbac_policy_from_url() {
    log_info "Setting up RBAC policy from URL: $RBAC_POLICY_FILE_URL"

    # Create PVC for RBAC policy
    log_info "Creating PVC for RBAC policy"
    envsubst <template/backstage/helm/rbac-policy-pvc.yaml | $clin apply -f -

    # Wait for PVC to be bound
    log_info "Waiting for RBAC policy PVC to be bound"
    $clin wait --for=jsonpath='{.status.phase}'=Bound pvc/rbac-policy-pvc --timeout=120s || {
        log_warn "PVC not bound yet, checking status..."
        $clin get pvc rbac-policy-pvc -o yaml
    }

    # Delete previous job if exists
    $clin delete job rbac-policy-download --ignore-not-found=true --wait

    # Create and run the download job
    log_info "Creating RBAC policy download job"
    envsubst <template/backstage/helm/rbac-policy-download-job.yaml | $clin apply -f -

    # Wait for the job to complete
    log_info "Waiting for RBAC policy download job to complete"
    $clin wait --for=condition=complete job/rbac-policy-download --timeout=300s || {
        log_error "RBAC policy download job failed"
        $clin logs job/rbac-policy-download
        return 1
    }

    log_info "RBAC policy download job completed successfully"
    $clin logs job/rbac-policy-download
}

delete_rbac_policy_pvc() {
    log_info "Deleting RBAC policy PVC and related resources"
    $clin delete job rbac-policy-download --ignore-not-found=true --wait
    $clin delete pvc rbac-policy-pvc --ignore-not-found=true --wait
}

restart_rhdh_deployment() {
    replica_count=${1:-1}
    if [ "$INSTALL_METHOD" == "helm" ]; then
        rhdh_deployment="${RHDH_HELM_RELEASE_NAME}-developer-hub"
    elif [ "$INSTALL_METHOD" == "olm" ]; then
        rhdh_deployment="backstage-developer-hub"
    fi
    # Check if the RHDH deployment exists before trying to scale or operate on it
    if ! $clin get deployment "$rhdh_deployment" &>/dev/null; then
        log_error "Deployment $rhdh_deployment does not exist. Skipping RHDH restart."
        return 1
    fi
    $clin scale deployment "$rhdh_deployment" --replicas=0
    for ((replicas = 1; replicas <= replica_count; replicas++)); do
        log_info "Scaling developer-hub deployment to $replicas/$replica_count replicas"
        $clin scale deployment "$rhdh_deployment" --replicas=$replicas
        wait_to_start deployment "$rhdh_deployment" 300 300
    done
}

# shellcheck disable=SC2016,SC1004
install_rhdh_with_helm() {
    chart_values_template=template/backstage/helm/chart-values.yaml
    if [ -n "${RHDH_IMAGE_REGISTRY}${RHDH_IMAGE_REPO}${RHDH_IMAGE_TAG}" ]; then
        echo "Using '$RHDH_IMAGE_REGISTRY/$RHDH_IMAGE_REPO:$RHDH_IMAGE_TAG' image for RHDH"
        chart_values_template=template/backstage/helm/chart-values.image-override.yaml
    fi
    version_arg=""
    chart_origin=$RHDH_HELM_REPO
    if [ -n "${RHDH_HELM_CHART_VERSION}" ]; then
        version_arg="--version $RHDH_HELM_CHART_VERSION"
        chart_origin="$chart_origin@$RHDH_HELM_CHART_VERSION"
    fi

    cp "$chart_values_template" "$TMP_DIR/chart-values.temp.yaml"

    # OAuth2 Proxy
    log_info "Setting up OAuth2 Proxy"
    if [ "${AUTH_PROVIDER}" == "keycloak" ]; then yq -i '.upstream.backstage |= . + load("template/backstage/helm/oauth2-container-patch.yaml")' "$TMP_DIR/chart-values.temp.yaml"; fi
    if [ "${AUTH_PROVIDER}" == "keycloak" ]; then yq -i '.upstream.service.ports.targetPort = "oauth2-proxy"' "$TMP_DIR/chart-values.temp.yaml"; fi
    if [ "${AUTH_PROVIDER}" == "keycloak" ]; then yq -i '.upstream.service.ports.backend = 4180' "$TMP_DIR/chart-values.temp.yaml"; fi

    # RBAC
    if ${ENABLE_RBAC}; then
        log_info "Setting up RBAC"
        if ${RBAC_POLICY_UPLOAD_TO_GITHUB} || [ -n "${RBAC_POLICY_FILE_URL}" ]; then
            log_info "Using RBAC policy from URL with PVC mount"
            yq -i '.upstream.backstage |= . + load("template/backstage/helm/extravolume-patch-rbac-pvc.yaml")' "$TMP_DIR/chart-values.temp.yaml"
        else
            yq -i '.upstream.backstage |= . + load("template/backstage/helm/extravolume-patch-1.x.yaml")' "$TMP_DIR/chart-values.temp.yaml"
        fi
        yq -i '.global.dynamic.plugins |= . + load("template/backstage/helm/rbac-plugin-patch.yaml")' "$TMP_DIR/chart-values.temp.yaml"
    fi

    # Pod affinity for multiple replicas to schedule on same node
    if [ "${RHDH_DEPLOYMENT_REPLICAS}" -gt 1 ]; then
        log_info "Applying pod affinity for multiple replicas to schedule on same node"
        yq -i '.upstream.backstage |= . + load("template/backstage/helm/pod-affinity-patch.yaml")' "$TMP_DIR/chart-values.temp.yaml"
    fi

    log_info "Installing RHDH Helm chart $RHDH_HELM_RELEASE_NAME from $chart_origin in $RHDH_NAMESPACE namespace"

    envsubst \
        '${OPENSHIFT_APP_DOMAIN} \
            ${RHDH_HELM_RELEASE_NAME} \
            ${RHDH_HELM_CHART} \
            ${RHDH_DEPLOYMENT_REPLICAS} \
            ${RHDH_DB_REPLICAS} \
            ${RHDH_DB_MAX_CONNECTIONS} \
            ${RHDH_DB_STORAGE} \
            ${RHDH_IMAGE_REGISTRY} \
            ${RHDH_IMAGE_REPO} \
            ${RHDH_IMAGE_TAG} \
            ${RHDH_NAMESPACE} \
            ${RHDH_METRIC} \
            ${RHDH_LOG_LEVEL} \
            ${COOKIE_SECRET} \
            ' <"$TMP_DIR/chart-values.temp.yaml" >"$TMP_DIR/chart-values.yaml"

    # Orchestrator
    if ${ENABLE_ORCHESTRATOR}; then
        log_info "Enabling orchestrator plugins"
        yq -i '.orchestrator.enabled = true' "$TMP_DIR/chart-values.yaml"
        yq -i ".orchestrator.sonataflowPlatform.externalDBHost=\"${POSTGRES_HOST}\"" "$TMP_DIR/chart-values.yaml"
        yq -i ".orchestrator.sonataflowPlatform.externalDBPort=\"${POSTGRES_PORT}\"" "$TMP_DIR/chart-values.yaml"
        if [[ "${ENABLE_PGBOUNCER}" == "true" && "${PGBOUNCER_REPLICAS}" -gt 0 ]]; then
            yq -i '.orchestrator.sonataflowPlatform.externalDBsecretRef="rhdh-db-sonataflow-credentials"' "$TMP_DIR/chart-values.yaml"
        else
            yq -i '.orchestrator.sonataflowPlatform.externalDBsecretRef="rhdh-db-credentials"' "$TMP_DIR/chart-values.yaml"
        fi
        yq -i '.orchestrator.sonataflowPlatform.externalDBName="postgres"' "$TMP_DIR/chart-values.yaml"
    fi

    # RHDH resources
    log_info "Setting up RHDH resources"
    if [ -n "${RHDH_RESOURCES_CPU_REQUESTS}" ]; then yq -i '.upstream.backstage.resources.requests.cpu = "'"${RHDH_RESOURCES_CPU_REQUESTS}"'"' "$TMP_DIR/chart-values.yaml"; fi
    if [ -n "${RHDH_RESOURCES_CPU_LIMITS}" ]; then yq -i '.upstream.backstage.resources.limits.cpu = "'"${RHDH_RESOURCES_CPU_LIMITS}"'"' "$TMP_DIR/chart-values.yaml"; fi
    if [ -n "${RHDH_RESOURCES_MEMORY_REQUESTS}" ]; then yq -i '.upstream.backstage.resources.requests.memory = "'"${RHDH_RESOURCES_MEMORY_REQUESTS}"'"' "$TMP_DIR/chart-values.yaml"; fi
    if [ -n "${RHDH_RESOURCES_MEMORY_LIMITS}" ]; then yq -i '.upstream.backstage.resources.limits.memory = "'"${RHDH_RESOURCES_MEMORY_LIMITS}"'"' "$TMP_DIR/chart-values.yaml"; fi

    # NodeJS Profiling
    if ${ENABLE_PROFILING}; then
        log_info "Setting up NodeJS Profiling"
        yq -i '.upstream.backstage.command |= ["node", "--prof", "--heapsnapshot-signal=SIGUSR2", "packages/backend"]' "$TMP_DIR/chart-values.yaml"
        # Collecting the heap snapshot freezes the RHDH while getting and writting the heap snapshot to a file
        # which makes the out-of-the-box liveness/readiness probes (set to 10s period) unhappy
        # and makes the scheduler to restart the Pod(s).
        # The following patch prolongs the period to 5 minutes to avoid that to happen.
        yq -i '.upstream.backstage.readinessProbe |= {"httpGet":{"path":"/healthcheck","port":7007,"scheme":"HTTP"},"initialDelaySeconds":30,"timeoutSeconds":2,"periodSeconds":300,"successThreshold":1,"failureThreshold":3}' "$TMP_DIR/chart-values.yaml"
        yq -i '.upstream.backstage.livenessProbe |= {"httpGet":{"path":"/healthcheck","port":7007,"scheme":"HTTP"},"initialDelaySeconds":30,"timeoutSeconds":2,"periodSeconds":300,"successThreshold":1,"failureThreshold":3}' "$TMP_DIR/chart-values.yaml"
    fi

    # RHDH database connection
    yq -i '.upstream.backstage.appConfig.database.connection.host = "'"${POSTGRES_HOST}"'"' "$TMP_DIR/chart-values.yaml"

    # Initial RHDH replicas to 1 before scaling up
    yq -i '.upstream.backstage.replicas = 1' "$TMP_DIR/chart-values.yaml"

    # Install RHDH Helm chart
    #shellcheck disable=SC2086
    helm upgrade "${RHDH_HELM_RELEASE_NAME}" -i "${RHDH_HELM_REPO}" ${version_arg} -n "${RHDH_NAMESPACE}" --values "$TMP_DIR/chart-values.yaml"

    if ${ENABLE_ORCHESTRATOR}; then
        wait_to_start deployment "sonataflow-platform-data-index-service" 300 300
        wait_to_start deployment "sonataflow-platform-jobs-service" 300 300
        install_workflows
    fi

    wait_to_exist "${RHDH_NAMESPACE}" "deployment" "${RHDH_HELM_RELEASE_NAME}-developer-hub" 300

    # Patch deployment strategy to start replicas one by one
    log_info "Patching RHDH deployment strategy for sequential replica startup"
    $clin patch deployment "${RHDH_HELM_RELEASE_NAME}-developer-hub" --type='merge' -p '{"spec":{"strategy":{"type":"RollingUpdate","rollingUpdate":{"maxUnavailable":0,"maxSurge":1}}}}'

    if [[ ${ENABLE_ORCHESTRATOR} == "true" && "${ENABLE_PGBOUNCER}" == "true" && "${PGBOUNCER_REPLICAS}" -gt 0 ]]; then
        patch_sonataflow_flyway
    fi
    restart_rhdh_deployment 1

    return $?
}

install_rhdh_with_olm() {
    $clin create secret generic rhdh-backend-secret --from-literal=BACKEND_SECRET="$(mktemp -u XXXXXXXXXXX)"
    mark_resource_for_rhdh secret rhdh-backend-secret
    $clin create cm app-config-backend-secret --from-file=template/backstage/olm/app-config.rhdh.backend-secret.yaml
    mark_resource_for_rhdh cm app-config-backend-secret
    cp template/backstage/olm/dynamic-plugins.configmap.yaml "$TMP_DIR/dynamic-plugins.configmap.yaml"
    if ${ENABLE_RBAC}; then
        cat template/backstage/olm/rbac-plugin-patch.yaml >>"$TMP_DIR/dynamic-plugins.configmap.yaml"
    fi
    $clin apply -f "$TMP_DIR/dynamic-plugins.configmap.yaml"
    mark_resource_for_rhdh cm dynamic-plugins-rhdh
    set -x
    OLM_CHANNEL="${RHDH_OLM_CHANNEL}" UPSTREAM_IIB="${RHDH_OLM_INDEX_IMAGE}" NAMESPACE_SUBSCRIPTION="${RHDH_OPERATOR_NAMESPACE}" WATCH_EXT_CONF="${RHDH_OLM_WATCH_EXT_CONF}" ./install-rhdh-catalog-source.sh --install-operator "${RHDH_OLM_OPERATOR_PACKAGE:-rhdh}"
    set +x
    wait_for_crd backstages.rhdh.redhat.com

    if [ "$AUTH_PROVIDER" == "keycloak" ]; then
        envsubst <template/backstage/olm/rhdh-oauth2.deployment.yaml | $clin apply -f -
    fi

    backstage_yaml="$TMP_DIR/backstage.yaml"
    envsubst <template/backstage/olm/backstage.yaml >"$backstage_yaml"
    if [ -n "${RHDH_IMAGE_REGISTRY}${RHDH_IMAGE_REPO}${RHDH_IMAGE_TAG}" ]; then
        echo "Using '$RHDH_IMAGE_REGISTRY/$RHDH_IMAGE_REPO:$RHDH_IMAGE_TAG' image for RHDH"
        yq -i '(.spec.application.image |= "'"${RHDH_IMAGE_REGISTRY}/${RHDH_IMAGE_REPO}:${RHDH_IMAGE_TAG}"'")' "$backstage_yaml"
    fi
    if ${ENABLE_RBAC}; then
        rbac_policy='[{"name": "rbac-policy"}]'
        yq -i '(.spec.application.extraFiles.configMaps |= (. // []) + '"$rbac_policy"')' "$backstage_yaml"
    fi
    $clin apply -f "$backstage_yaml"

    wait_to_start statefulset "backstage-psql-developer-hub" 300 300
    wait_to_start deployment "backstage-developer-hub" 300 300
    return $?
}

backstage_install() {
    log_info "Installing RHDH with install method: $INSTALL_METHOD"
    cp "template/backstage/app-config.yaml" "$TMP_DIR/app-config.yaml"
    if [ "${AUTH_PROVIDER}" == "keycloak" ]; then yq -i '. |= . + {"signInPage":"oauth2Proxy"}' "$TMP_DIR/app-config.yaml"; fi
    if [ "${AUTH_PROVIDER}" == "keycloak" ]; then yq -i '. |= . + {"auth":{"environment":"production","providers":{"oauth2Proxy":{}}}}' "$TMP_DIR/app-config.yaml"; else yq -i '. |= . + {"auth":{"providers":{"guest":{"dangerouslyAllowOutsideDevelopment":true}}}}' "$TMP_DIR/app-config.yaml"; fi

    if ${ENABLE_ORCHESTRATOR}; then
        install_orchestrator_infra
    fi
    until envsubst <template/backstage/secret-rhdh-pull-secret.yaml | $clin apply -f -; do $clin delete secret rhdh-pull-secret --ignore-not-found=true; done
    if ${ENABLE_RBAC}; then yq -i '. |= . + load("template/backstage/'$INSTALL_METHOD'/app-rbac-patch.yaml")' "$TMP_DIR/app-config.yaml"; fi
    if ${PRE_LOAD_DB}; then
        echo "locations: []" >"$TMP_DIR/locations.yaml"
        create_objs
        yq -i '.catalog.locations |= . + load("'"$TMP_DIR/locations.yaml"'").locations' "$TMP_DIR/app-config.yaml"
    fi
    until $clin create configmap app-config-rhdh --from-file "app-config.rhdh.yaml=$TMP_DIR/app-config.yaml"; do $clin delete configmap app-config-rhdh --ignore-not-found=true; done
    if ${ENABLE_RBAC}; then
        if ${RBAC_POLICY_UPLOAD_TO_GITHUB}; then
            log_info "RBAC policy will be generated and uploaded to GitHub"
            create_and_upload_rbac_policy_csv "$RBAC_POLICY"
            log_info "RBAC policy uploaded to GitHub. URL: $RBAC_POLICY_FILE_URL"
            setup_rbac_policy_from_url
        elif [ -n "${RBAC_POLICY_FILE_URL}" ]; then
            log_info "RBAC policy will be downloaded from URL: $RBAC_POLICY_FILE_URL"
            setup_rbac_policy_from_url
        else
            cp template/backstage/rbac-config.yaml "${TMP_DIR}/rbac-config.yaml"
            if [[ $RBAC_POLICY == "$RBAC_POLICY_COMPLEX" ]]; then
                cat template/backstage/complex-rbac-config.csv >>"${TMP_DIR}/rbac-config.yaml"
            fi
            create_rbac_policy "$RBAC_POLICY"
            cat "$TMP_DIR/group-rbac.yaml" >>"$TMP_DIR/rbac-config.yaml"
            if [[ "$INSTALL_METHOD" == "helm" ]] && ${ENABLE_ORCHESTRATOR}; then
                cat template/backstage/helm/orchestrator-rbac-patch.yaml >>"$TMP_DIR/rbac-config.yaml"
                if [[ $RBAC_POLICY == "$RBAC_POLICY_COMPLEX" ]]; then
                    cat template/backstage/helm/complex-orchestrator-rbac-patch.yaml >>"${TMP_DIR}/rbac-config.yaml"
                fi
            fi
            until $clin create -f "$TMP_DIR/rbac-config.yaml"; do $clin delete configmap rbac-policy --ignore-not-found=true; done
        fi
    fi
    envsubst <template/backstage/plugin-secrets.yaml | $clin apply -f -
    until $clin create -f "template/backstage/techdocs-pvc.yaml"; do $clin delete pvc rhdh-techdocs --ignore-not-found=true; done

    setup_rhdh_db

    if [ "$INSTALL_METHOD" == "helm" ]; then
        install_rhdh_with_helm
        install_exit_code=$?
    elif [ "$INSTALL_METHOD" == "olm" ]; then
        install_rhdh_with_olm
        install_exit_code=$?
    else
        log_error "Invalid install method: $INSTALL_METHOD, currently allowed methods are helm or olm"
        exit 1
    fi
    date -u -Ins >"${TMP_DIR}/populate-before"
    # shellcheck disable=SC2064
    trap "date -u -Ins >'${TMP_DIR}/populate-after'" RETURN EXIT

    if ${RHDH_METRIC}; then
        log_info "Setting up RHDH metrics"
        if [ "${AUTH_PROVIDER}" == "keycloak" ]; then
            $clin create -f template/backstage/rhdh-metrics-service.yaml
        fi
        envsubst <template/backstage/rhdh-servicemonitor.yaml | $clin create -f -
    fi
    if [ "$install_exit_code" -ne 0 ]; then
        log_error "RHDH installation with install method $INSTALL_METHOD failed"
        return $install_exit_code
    fi
    log_info "RHDH Installed, waiting for the catalog to be populated"
    timeout=600
    timeout_timestamp=$(python3 -c "from datetime import datetime, timedelta; t_add=int('$timeout'); print(int((datetime.now() + timedelta(seconds=t_add)).timestamp()))")
    last_count=-1
    for entity_type in User Group Component API; do
        while true; do
            if [ "$(date "+%s")" -gt "$timeout_timestamp" ]; then
                log_error "Timeout waiting on '$entity_type' count"
                exit 1
            else
                b_count=$(get_catalog_entity_count "$entity_type")
                if [[ 'User' == "$entity_type" ]]; then
                    # Add 1 to account for the "guru" user that's always present
                    e_count=$((BACKSTAGE_USER_COUNT + 1))
                elif [[ 'Group' == "$entity_type" ]]; then
                    e_count=$GROUP_COUNT
                elif [[ 'Component' == "$entity_type" ]]; then
                    e_count=$COMPONENT_COUNT
                elif [[ 'API' == "$entity_type" ]]; then
                    e_count=$API_COUNT
                fi
                if [[ "$last_count" != "$b_count" ]]; then # reset the timeout if current count changes
                    log_info "The current '$entity_type' count changed, resetting waiting timeout to $timeout seconds"
                    timeout_timestamp=$(python3 -c "from datetime import datetime, timedelta; t_add=int('$timeout'); print(int((datetime.now() + timedelta(seconds=t_add)).timestamp()))")
                    last_count=$b_count
                fi
                if [[ $b_count -ge $e_count ]]; then
                    log_info "The '$entity_type' count reached expected value ($b_count)"
                    break
                fi
            fi
            log_info "Waiting for the '$entity_type' count to be ${e_count} (current: ${b_count})"
            sleep 10s
        done
    done
}

###############################################################################
# Section 7: Monitoring
###############################################################################

setup_monitoring() {
    log_info "Ensuring Prometheus persistent storage"
    config="$TMP_DIR/cluster-monitoring-config.yaml"
    rm -rvf "$config"
    if $cli -n openshift-monitoring get cm cluster-monitoring-config; then
        $cli -n openshift-monitoring extract configmap/cluster-monitoring-config --to=- --keys=config.yaml >"$config"
    else
        echo "" >"$config"
        $cli -n openshift-monitoring create configmap cluster-monitoring-config --from-file=config.yaml="$config"
    fi

    update_config=0
    if [ "$(yq '.enableUserWorkload' "$config")" != "true" ]; then
        yq -i '.enableUserWorkload = true' "$config"
        update_config=1
    fi

    if [ "$(yq '.prometheusK8s.volumeClaimTemplate' "$config")" == "null" ]; then
        yq -i '.prometheusK8s = {"volumeClaimTemplate":{"spec":{"storageClassName":"gp3-csi","volumeMode":"Filesystem","resources":{"requests":{"storage":"60Gi"}}}}}' "$config"
        update_config=1
    fi

    if [ $update_config -gt 0 ]; then
        log_info "Updating cluster monitoring config"
        $cli -n openshift-monitoring set data configmap/cluster-monitoring-config --from-file=config.yaml="$config"

        log_info "Restarting Prometheus"
        oc -n openshift-monitoring rollout restart statefulset/prometheus-k8s
        oc -n openshift-monitoring rollout status statefulset/prometheus-k8s -w
    fi

    # Setup user workload monitoring
    log_info "Enabling user workload monitoring"
    before=$(date -u +%s)
    while true; do
        count=$(kubectl -n "openshift-user-workload-monitoring" get StatefulSet -l operator.prometheus.io/name=user-workload -o name 2>/dev/null | wc -l)
        [ "$count" -gt 0 ] && break
        now=$(date -u +%s)
        if [[ $((now - before)) -ge "300" ]]; then
            log_error "Required StatefulSet did not appeared before timeout"
            exit 1
        fi
        sleep 3
    done

    kubectl -n openshift-user-workload-monitoring rollout status --watch --timeout=600s StatefulSet/prometheus-user-workload
    kubectl -n openshift-user-workload-monitoring wait --for=condition=ready pod -l app.kubernetes.io/component=prometheus
    kubectl -n openshift-user-workload-monitoring get pod

    config="$TMP_DIR/user-workload-monitoring-config.yaml"
    rm -rvf "$config"
    if $cli -n openshift-user-workload-monitoring get cm user-workload-monitoring-config; then
        $cli -n openshift-user-workload-monitoring extract configmap/user-workload-monitoring-config --to=- --keys=config.yaml >"$config"
    else
        $cli -n openshift-user-workload-monitoring create configmap user-workload-monitoring-config
        echo "" >"$config"
    fi

    if [ "$(yq '.prometheus.volumeClaimTemplate' "$config")" == "null" ]; then
        yq -i '.prometheus = {"volumeClaimTemplate":{"spec":{"storageClassName":"gp3-csi","volumeMode":"Filesystem","resources":{"requests":{"storage":"10Gi"}}}}}' "$config"
        log_info "Updating user workload monitoring config"
        $cli -n openshift-user-workload-monitoring set data configmap/user-workload-monitoring-config --from-file=config.yaml="$config"

        log_info "Restarting User Workload Prometheus"
        oc -n openshift-user-workload-monitoring rollout restart statefulset/prometheus-user-workload
        oc -n openshift-user-workload-monitoring rollout status statefulset/prometheus-user-workload -w
    fi

    log_info "Setting up Locust monitoring"
    envsubst <template/locust-metrics/locust-service-monitor.yaml | kubectl -n "${LOCUST_NAMESPACE}" apply -f -
}

###############################################################################
# Section 8: Cleanup & Delete
###############################################################################

delete_rhdh_with_olm() {
    $clin delete backstage developer-hub --ignore-not-found=true --wait
    $cli delete namespace "$RHDH_NAMESPACE" --ignore-not-found=true --wait

    $cli -n "$RHDH_OPERATOR_NAMESPACE" delete subscriptions.operators.coreos.com rhdh --ignore-not-found=true --wait
    for i in $($cli get catsrc -n openshift-marketplace -o json | jq -rc '.items[] | select(.metadata.name | startswith("rhdh")).metadata.name'); do
        $cli -n openshift-marketplace delete catsrc "$i" --ignore-not-found=true --wait
    done
    $cli delete namespace "$RHDH_OPERATOR_NAMESPACE" --ignore-not-found=true --wait
    $cli delete crd backstages.rhdh.redhat.com --ignore-not-found=true --wait
}

delete() {
    log_info "Remove RHDH with install method: $INSTALL_METHOD"
    if [ "$INSTALL_METHOD" == "helm" ]; then
        log_info "Uninstalling RHDH Helm release"
        helm uninstall "${RHDH_HELM_RELEASE_NAME}" --namespace "${RHDH_NAMESPACE}"
        $clin delete pvc "data-${RHDH_HELM_RELEASE_NAME}-postgresql-0" --ignore-not-found=true
        # Clean up RBAC policy PVC if it exists
        delete_rbac_policy_pvc
        envsubst <template/backstage/rhdh-db/postgres-cluster.yaml | $clin delete -f - --ignore-not-found=true --wait
        envsubst <template/backstage/rhdh-db/crunchy-postgres-op.yaml | $clin delete -f - --ignore-not-found=true --wait
        $cli delete ns "${RHDH_NAMESPACE}" --ignore-not-found=true --wait
    elif [ "$INSTALL_METHOD" == "olm" ]; then
        delete_rhdh_with_olm
    fi
    if ${ENABLE_ORCHESTRATOR}; then
        if ${FORCE_ORCHESTRATOR_INFRA_UNINSTALL}; then
            log_info "FORCE_ORCHESTRATOR_INFRA_UNINSTALL=true, uninstalling existing orchestrator infra if present"
            delete_orchestrator_infra
        fi
    fi
}

###############################################################################
# Section 9: Main Entry Point
###############################################################################

install() {
    if [ "$INSTALL_METHOD" != "helm" ] && ${ENABLE_ORCHESTRATOR}; then
        log_error "Orchestrator is only supported with Helm install method"
        return 1
    fi
    setup_rhdh_namespace
    setup_operator_group
    setup_monitoring
    appurl=$(oc whoami --show-console)
    export OPENSHIFT_APP_DOMAIN=${appurl#*.}

    keycloak_install 2>&1 | tee "${TMP_DIR}/keycloak_install.log"

    if $PRE_LOAD_DB; then
        log_info "Creating users and groups in Keycloak in background"
        create_users_groups 2>&1 | tee -a "${TMP_DIR}/create-users-groups.log"
    fi

    backstage_install 2>&1 | tee -a "${TMP_DIR}/backstage-install.log"
    exit_code=${PIPESTATUS[0]}
    if [ "$exit_code" -ne 0 ]; then
        log_error "Installation failed!!!"
        return "$exit_code"
    fi

    psql_debug

    log_info "Scaling RHDH deployment to $RHDH_DEPLOYMENT_REPLICAS replicas"
    restart_rhdh_deployment "$RHDH_DEPLOYMENT_REPLICAS"
}

###############################################################################
# Section 10: CLI Parsing
###############################################################################

while getopts "oi:mrdwcWCeE" flag; do
    case "${flag}" in
    o)
        export INSTALL_METHOD=olm
        ;;
    r)
        delete
        install
        ;;
    d)
        delete
        ;;
    i)
        AUTH_PROVIDER="$OPTARG"
        install
        ;;
    w)
        if [ "$INSTALL_METHOD" == "helm" ]; then
            install_workflows
        elif [ "$INSTALL_METHOD" == "olm" ]; then
            log_info "Orchestrator workflows are not supported with OLM"
        fi
        ;;
    W)
        if [ "$INSTALL_METHOD" == "helm" ]; then
            uninstall_workflows
        elif [ "$INSTALL_METHOD" == "olm" ]; then
            log_info "Orchestrator workflows are not supported with OLM"
        fi
        ;;
    m)
        setup_monitoring
        ;;
    c)
        setup_rhdh_db
        ;;
    C)
        delete_rhdh_db
        ;;
    e)
        psql_debug
        ;;
    E)
        psql_debug_cleanup
        ;;
    \?)
        log_warn "Invalid option: ${flag} - defaulting to -i (install)"
        install
        ;;
    esac
done
