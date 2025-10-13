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
export RHDH_KEYCLOAK_REPLICAS=${RHDH_KEYCLOAK_REPLICAS:-1}

export RHDH_IMAGE_REGISTRY=${RHDH_IMAGE_REGISTRY:-}
export RHDH_IMAGE_REPO=${RHDH_IMAGE_REPO:-}
export RHDH_IMAGE_TAG=${RHDH_IMAGE_TAG:-}

export RHDH_BASE_VERSION=${RHDH_BASE_VERSION:-1.8}

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
export RHDH_LOG_LEVEL="${RHDH_LOG_LEVEL:-warn}"

export PSQL_LOG="${PSQL_LOG:-true}"
export RHDH_METRIC="${RHDH_METRIC:-true}"
export PSQL_EXPORT="${PSQL_EXPORT:-false}"
export LOG_MIN_DURATION_STATEMENT="${LOG_MIN_DURATION_STATEMENT:-65}"
export LOG_MIN_DURATION_SAMPLE="${LOG_MIN_DURATION_SAMPLE:-50}"
export LOG_STATEMENT_SAMPLE_RATE="${LOG_STATEMENT_SAMPLE_RATE:-0.7}"

export INSTALL_METHOD=helm

TMP_DIR=$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "${TMP_DIR:-.tmp}")
mkdir -p "${TMP_DIR}"

wait_to_start_in_namespace() {
    namespace=${1:-${RHDH_NAMESPACE}}
    resource=${2:-deployment}
    name=${3:-name}
    initial_timeout=${4:-300}
    wait_timeout=${5:-300}
    rn=$resource/$name
    description=${6:-$rn}
    timeout_timestamp=$(python3 -c "from datetime import datetime, timedelta; t_add=int('$initial_timeout'); print(int((datetime.now() + timedelta(seconds=t_add)).timestamp()))")

    interval=10s
    while ! /bin/bash -c "$cli -n $namespace get $rn -o name"; do
        if [ "$(date "+%s")" -gt "$timeout_timestamp" ]; then
            log_error "Timeout waiting for $description to start"
            exit 1
        else
            log_info "Waiting $interval for $description to start..."
            sleep "$interval"
        fi
    done
    $cli -n "$namespace" rollout status "$rn" --timeout="${wait_timeout}s"
    return $?
}

wait_for_crd() {
    name=${1:-name}
    initial_timeout=${2:-300}
    rn=crd/$name
    description=${3:-$rn}
    timeout_timestamp=$(python3 -c "from datetime import datetime, timedelta; t_add=int('$initial_timeout'); print(int((datetime.now() + timedelta(seconds=t_add)).timestamp()))")
    interval=10s
    while ! /bin/bash -c "$cli get $rn"; do
        if [ "$(date "+%s")" -gt "$timeout_timestamp" ]; then
            log_error "Timeout waiting for $description to exist"
            exit 1
        else
            log_info "Waiting $interval for $description to exist..."
            sleep "$interval"
        fi
    done
}

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

wait_to_start() {
    wait_to_start_in_namespace "$RHDH_NAMESPACE" "$@"
    return $?
}

label() {
    namespace=$1
    resource=$2
    name=$3
    label=$4
    $cli -n "$namespace" label "$resource" "$name" "$label"
}

label_n() {
    label "$RHDH_NAMESPACE" "$1" "$2" "$3"
}

annotate() {
    namespace=$1
    resource=$2
    name=$3
    annotation=$4
    $cli -n "$namespace" annotate "$resource" "$name" "$annotation"
}

annotate_n() {
    annotate "$RHDH_NAMESPACE" "$1" "$2" "$3"
}

mark_resource_for_rhdh() {
    resource=$1
    name=$2
    annotate_n "$resource" "$name" "rhdh.redhat.com/backstage-name=developer-hub"
    label_n "$resource" "$name" "rhdh.redhat.com/ext-config-sync=true"
}

install() {
    if [ "$INSTALL_METHOD" != "helm" ] && ${ENABLE_ORCHESTRATOR}; then
        log_error "Orchestrator is only supported with Helm install method"
        return 1
    fi
    setup_monitoring
    appurl=$(oc whoami --show-console)
    export OPENSHIFT_APP_DOMAIN=${appurl#*.}
    $cli create namespace "${RHDH_NAMESPACE}" --dry-run=client -o yaml | $cli apply -f -
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

    if ${ENABLE_ORCHESTRATOR}; then
        install_workflows
    fi
    psql_debug
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
    envsubst <template/keycloak/keycloak.yaml | $clin apply -f -
    wait_to_start statefulset rhdh-keycloak 450 600
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
}

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

backstage_install() {
    log_info "Installing RHDH with install method: $INSTALL_METHOD"
    cp "template/backstage/app-config.yaml" "$TMP_DIR/app-config.yaml"
    if [ "${AUTH_PROVIDER}" == "keycloak" ]; then yq -i '. |= . + {"signInPage":"oauth2Proxy"}' "$TMP_DIR/app-config.yaml"; fi
    if [ "${AUTH_PROVIDER}" == "keycloak" ]; then yq -i '. |= . + {"auth":{"environment":"production","providers":{"oauth2Proxy":{}}}}' "$TMP_DIR/app-config.yaml"; else yq -i '. |= . + {"auth":{"providers":{"guest":{"dangerouslyAllowOutsideDevelopment":true}}}}' "$TMP_DIR/app-config.yaml"; fi

    if ${ENABLE_ORCHESTRATOR}; then
        install_orchestrator_infra

        yq -i '.orchestrator.dataIndexService.url="http://sonataflow-platform-data-index-service.'"$RHDH_NAMESPACE"'"' "$TMP_DIR/app-config.yaml"
        yq -i '.orchestrator.enabled=true' "$TMP_DIR/app-config.yaml"
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
        cp template/backstage/rbac-config.yaml "${TMP_DIR}/rbac-config.yaml"
        if [[ $RBAC_POLICY == "$RBAC_POLICY_REALISTIC" ]]; then
            cat template/backstage/realistic-rbac-config.yaml >>"${TMP_DIR}/rbac-config.yaml"
        fi
        create_rbac_policy "$RBAC_POLICY"
        cat "$TMP_DIR/group-rbac.yaml" >>"$TMP_DIR/rbac-config.yaml"
        if [[ "$INSTALL_METHOD" == "helm" ]] && ${ENABLE_ORCHESTRATOR}; then
            cat template/backstage/helm/orchestrator-rbac-patch.yaml >>"$TMP_DIR/rbac-config.yaml"
            if [[ $RBAC_POLICY == "$RBAC_POLICY_REALISTIC" ]]; then
                cat template/backstage/helm/realistic-orchestrator-rbac-patch.yaml >>"${TMP_DIR}/rbac-config.yaml"
            fi
        fi
        until $clin create -f "$TMP_DIR/rbac-config.yaml"; do $clin delete configmap rbac-policy --ignore-not-found=true; done
    fi
    envsubst <template/backstage/plugin-secrets.yaml | $clin apply -f -
    until $clin create -f "template/backstage/techdocs-pvc.yaml"; do $clin delete pvc rhdh-techdocs --ignore-not-found=true; done
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

install_workflows() {
    log_info "Installing Orchestrator workflows"
    mkdir -p "$TMP_DIR/workflows"
    find template/workflows/basic -type f -print0 | while IFS= read -r -d '' i; do
        # shellcheck disable=SC2094
        envsubst <"$i" >"$TMP_DIR/workflows/$(basename "$i")"
        $clin apply -f "$TMP_DIR/workflows/$(basename "$i")"
    done
}

uninstall_workflows() {
    log_info "Uninstalling Orchestrator workflows"
    $clin delete -f template/workflows/basic --ignore-not-found=true || true
}

# shellcheck disable=SC2016,SC1004
install_rhdh_with_helm() {
    chart_values=template/backstage/helm/chart-values.yaml
    if [ -n "${RHDH_IMAGE_REGISTRY}${RHDH_IMAGE_REPO}${RHDH_IMAGE_TAG}" ]; then
        echo "Using '$RHDH_IMAGE_REGISTRY/$RHDH_IMAGE_REPO:$RHDH_IMAGE_TAG' image for RHDH"
        chart_values=template/backstage/helm/chart-values.image-override.yaml
    fi
    version_arg=""
    chart_origin=$RHDH_HELM_REPO
    if [ -n "${RHDH_HELM_CHART_VERSION}" ]; then
        version_arg="--version $RHDH_HELM_CHART_VERSION"
        chart_origin="$chart_origin@$RHDH_HELM_CHART_VERSION"
    fi
    log_info "Installing RHDH Helm chart $RHDH_HELM_RELEASE_NAME from $chart_origin in $RHDH_NAMESPACE namespace"
    cp "$chart_values" "$TMP_DIR/chart-values.temp.yaml"
    if [ "${AUTH_PROVIDER}" == "keycloak" ]; then yq -i '.upstream.backstage |= . + load("template/backstage/helm/oauth2-container-patch.yaml")' "$TMP_DIR/chart-values.temp.yaml"; fi
    if ${ENABLE_RBAC}; then
        yq -i '.upstream.backstage |= . + load("template/backstage/helm/extravolume-patch-1.x.yaml")' "$TMP_DIR/chart-values.temp.yaml"
        yq -i '.global.dynamic.plugins |= . + load("template/backstage/helm/rbac-plugin-patch.yaml")' "$TMP_DIR/chart-values.temp.yaml"
    fi
    if ${ENABLE_ORCHESTRATOR}; then
        log_info "Enabling orchestrator plugins"
        yq -i '.orchestrator.enabled = true' "$TMP_DIR/chart-values.temp.yaml"
    fi
    if [ "${RHDH_DEPLOYMENT_REPLICAS}" -gt 1 ]; then
        log_info "Applying pod affinity for multiple replicas to schedule on same node"
        yq -i '.upstream.backstage |= . + load("template/backstage/helm/pod-affinity-patch.yaml")' "$TMP_DIR/chart-values.temp.yaml"
    fi
    envsubst \
        '${OPENSHIFT_APP_DOMAIN} \
            ${RHDH_HELM_RELEASE_NAME} \
            ${RHDH_HELM_CHART} \
            ${RHDH_DEPLOYMENT_REPLICAS} \
            ${RHDH_DB_REPLICAS} \
            ${RHDH_DB_STORAGE} \
            ${RHDH_IMAGE_REGISTRY} \
            ${RHDH_IMAGE_REPO} \
            ${RHDH_IMAGE_TAG} \
            ${RHDH_NAMESPACE} \
            ${RHDH_METRIC} \
            ${RHDH_LOG_LEVEL} \
            ${COOKIE_SECRET} \
            ' <"$TMP_DIR/chart-values.temp.yaml" >"$TMP_DIR/chart-values.yaml"
    if [ -n "${RHDH_RESOURCES_CPU_REQUESTS}" ]; then yq -i '.upstream.backstage.resources.requests.cpu = "'"${RHDH_RESOURCES_CPU_REQUESTS}"'"' "$TMP_DIR/chart-values.yaml"; fi
    if [ -n "${RHDH_RESOURCES_CPU_LIMITS}" ]; then yq -i '.upstream.backstage.resources.limits.cpu = "'"${RHDH_RESOURCES_CPU_LIMITS}"'"' "$TMP_DIR/chart-values.yaml"; fi
    if [ -n "${RHDH_RESOURCES_MEMORY_REQUESTS}" ]; then yq -i '.upstream.backstage.resources.requests.memory = "'"${RHDH_RESOURCES_MEMORY_REQUESTS}"'"' "$TMP_DIR/chart-values.yaml"; fi
    if [ -n "${RHDH_RESOURCES_MEMORY_LIMITS}" ]; then yq -i '.upstream.backstage.resources.limits.memory = "'"${RHDH_RESOURCES_MEMORY_LIMITS}"'"' "$TMP_DIR/chart-values.yaml"; fi
    if [ "${AUTH_PROVIDER}" == "keycloak" ]; then yq -i '.upstream.service.ports.targetPort = "oauth2-proxy"' "$TMP_DIR/chart-values.yaml"; fi
    if [ "${AUTH_PROVIDER}" == "keycloak" ]; then yq -i '.upstream.service.ports.backend = 4180' "$TMP_DIR/chart-values.yaml"; fi
    if ${ENABLE_PROFILING}; then
        yq -i '.upstream.backstage.command |= ["node", "--prof", "--heapsnapshot-signal=SIGUSR1", "packages/backend"]' "$TMP_DIR/chart-values.yaml"
        # Collecting the heap snapshot freezes the RHDH while getting and writting the heap snapshot to a file
        # which makes the out-of-the-box liveness/readiness probes (set to 10s period) unhappy
        # and makes the scheduler to restart the Pod(s).
        # The following patch prolongs the period to 5 minutes to avoid that to happen.
        yq -i '.upstream.backstage.readinessProbe |= {"httpGet":{"path":"/healthcheck","port":7007,"scheme":"HTTP"},"initialDelaySeconds":30,"timeoutSeconds":2,"periodSeconds":300,"successThreshold":1,"failureThreshold":3}' "$TMP_DIR/chart-values.yaml"
        yq -i '.upstream.backstage.livenessProbe |= {"httpGet":{"path":"/healthcheck","port":7007,"scheme":"HTTP"},"initialDelaySeconds":30,"timeoutSeconds":2,"periodSeconds":300,"successThreshold":1,"failureThreshold":3}' "$TMP_DIR/chart-values.yaml"
    fi
    #shellcheck disable=SC2086
    helm upgrade "${RHDH_HELM_RELEASE_NAME}" -i ${RHDH_HELM_REPO} ${version_arg} -n "${RHDH_NAMESPACE}" --values "$TMP_DIR/chart-values.yaml"
    wait_to_start statefulset "${RHDH_HELM_RELEASE_NAME}-postgresql-read" 300 300
    wait_to_start deployment "${RHDH_HELM_RELEASE_NAME}-developer-hub" 300 300
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

# shellcheck disable=SC2016,SC1001,SC2086
psql_debug() {
    if [ "$INSTALL_METHOD" == "helm" ]; then
        psql_db_ss="${RHDH_HELM_RELEASE_NAME}-postgresql-primary"
        psql_db="${psql_db_ss}-0"
        rhdh_deployment="${RHDH_HELM_RELEASE_NAME}-developer-hub"
    elif [ "$INSTALL_METHOD" == "olm" ]; then
        psql_db_ss=backstage-psql-developer-hub
        psql_db="${psql_db_ss}-0"
        rhdh_deployment=backstage-developer-hub
    fi
    if ${PSQL_LOG}; then
        log_info "Setting up PostgreSQL logging"
        $clin exec "${psql_db}" -- sh -c "sed -i "s/^\s*#log_min_duration_statement.*/log_min_duration_statement=${LOG_MIN_DURATION_STATEMENT}/" /var/lib/pgsql/data/userdata/postgresql.conf "
        $clin exec "${psql_db}" -- sh -c "sed -i "s/^\s*#log_min_duration_sample.*/log_min_duration_sample=${LOG_MIN_DURATION_SAMPLE}/" /var/lib/pgsql/data/userdata/postgresql.conf "
        $clin exec "${psql_db}" -- sh -c "sed -i "s/^\s*#log_statement_sample_rate.*/log_statement_sample_rate=${LOG_STATEMENT_SAMPLE_RATE}/" /var/lib/pgsql/data/userdata/postgresql.conf "
    fi
    if ${PSQL_EXPORT}; then
        log_info "Setting up PostgreSQL tracking"
        $clin exec "${psql_db}" -- sh -c 'sed -i "s/^\s*#track_io_timing.*/track_io_timing = on/" /var/lib/pgsql/data/userdata/postgresql.conf'
        $clin exec "${psql_db}" -- sh -c 'sed -i "s/^\s*#track_wal_io_timing.*/track_wal_io_timing = on/" /var/lib/pgsql/data/userdata/postgresql.conf'
        $clin exec "${psql_db}" -- sh -c 'sed -i "s/^\s*#track_functions.*/track_functions = all/" /var/lib/pgsql/data/userdata/postgresql.conf'
        $clin exec "${psql_db}" -- sh -c 'sed -i "s/^\s*#stats_fetch_consistency.*/stats_fetch_consistency = cache/" /var/lib/pgsql/data/userdata/postgresql.conf'
        $clin exec "${psql_db}" -- sh -c "echo shared_preload_libraries = \'pgaudit,auto_explain,pg_stat_statements\' >> /var/lib/pgsql/data/userdata/postgresql.conf"
    fi

    if ${PSQL_LOG} || ${PSQL_EXPORT}; then
        log_info "Restarting RHDH DB..."
        $clin rollout restart statefulset/"$psql_db_ss"
        wait_to_start statefulset "$psql_db_ss" 300 300
    fi

    if ${PSQL_EXPORT}; then
        log_info "Setting up PostgreSQL metrics exporter"
        $clin exec "${psql_db}" -- sh -c 'psql -c "CREATE EXTENSION pg_stat_statements;"'
        uid=$(oc get namespace "${RHDH_NAMESPACE}" -o go-template='{{ index .metadata.annotations "openshift.io/sa.scc.supplemental-groups" }}' | cut -d '/' -f 1)
        pg_pass=$(${clin} get secret rhdh-postgresql -o jsonpath='{.data.postgres-password}' | base64 -d)
        plugins=("backstage_plugin_permission" "backstage_plugin_auth" "backstage_plugin_catalog" "backstage_plugin_scaffolder" "backstage_plugin_search" "backstage_plugin_app")
        helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
        cp template/postgres-exporter/chart-values.yaml "$TMP_DIR/pg-exporter.yaml"
        sed -i "s/uid/$uid/g" "$TMP_DIR/pg-exporter.yaml"
        sed -i "s/pg_password/'$pg_pass'/g" "$TMP_DIR/pg-exporter.yaml"
        helm install pg-exporter prometheus-community/prometheus-postgres-exporter -n "${RHDH_NAMESPACE}" -f "$TMP_DIR/pg-exporter.yaml"
        for plugin in "${plugins[@]}"; do
            cp template/postgres-exporter/values-template.yaml "${TMP_DIR}/${plugin}.yaml"
            sed -i "s/'dbname'/'$plugin'/" "${TMP_DIR}/${plugin}.yaml"
            sed -i "s/uid/$uid/g" "${TMP_DIR}/${plugin}.yaml"
            sed -i "s/pg_password/'$pg_pass'/g" "${TMP_DIR}/${plugin}.yaml"
            helm_name=${plugin//_/-}
            helm install "${helm_name}" prometheus-community/prometheus-postgres-exporter -n "${RHDH_NAMESPACE}" -f "${TMP_DIR}/${plugin}.yaml"
        done
    fi

    if ${PSQL_LOG} || ${PSQL_EXPORT}; then
        log_info "Restarting RHDH..."
        $clin rollout restart deployment/"$rhdh_deployment"
        wait_to_start deployment "$rhdh_deployment" 300 300
    fi

    if ${PSQL_EXPORT}; then
        log_info "Setting up PostgreSQL monitoring"
        plugins=("pg-exporter" "backstage-plugin-permission" "backstage-plugin-auth" "backstage-plugin-catalog" "backstage-plugin-scaffolder" "backstage-plugin-search" "backstage-plugin-app")
        for plugin in "${plugins[@]}"; do
            cp template/postgres-exporter/service-monitor-template.yaml "${TMP_DIR}/${plugin}-monitor.yaml"
            sed -i "s/pglabel/$plugin/" "${TMP_DIR}/${plugin}-monitor.yaml"
            sed -i "s/pgnamespace/$RHDH_NAMESPACE/g" "${TMP_DIR}/${plugin}-monitor.yaml"
            $clin create -f "${TMP_DIR}/${plugin}-monitor.yaml"
        done
    fi
}

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
        yq -i '.prometheusK8s = {"volumeClaimTemplate":{"spec":{"storageClassName":"gp3-csi","volumeMode":"Filesystem","resources":{"requests":{"storage":"30Gi"}}}}}' "$config"
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

delete() {
    log_info "Remove RHDH with install method: $INSTALL_METHOD"
    if ! $cli get ns "$RHDH_NAMESPACE" >/dev/null; then
        log_info "$RHDH_NAMESPACE namespace does not exit... Skipping. "
    else
        for cr in keycloakusers keycloakclients keycloakrealms keycloaks; do
            for res in $($clin get "$cr.keycloak.org" -o name); do
                $clin patch "$res" -p '{"metadata":{"finalizers":[]}}' --type=merge
                $clin delete "$res" --wait
            done
        done
    fi
    if [ "$INSTALL_METHOD" == "helm" ]; then
        log_info "Uninstalling RHDH Helm release"
        helm uninstall "${RHDH_HELM_RELEASE_NAME}" --namespace "${RHDH_NAMESPACE}"
        $clin delete pvc "data-${RHDH_HELM_RELEASE_NAME}-postgresql-0" --ignore-not-found=true
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

while getopts "oi:mrdwW" flag; do
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
    \?)
        log_warn "Invalid option: ${flag} - defaulting to -i (install)"
        install
        ;;
    esac
done
