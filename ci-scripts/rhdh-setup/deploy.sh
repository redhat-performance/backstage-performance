#!/bin/bash
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1090,SC1091
source "$(readlink -m "$SCRIPT_DIR"/../../test.env)"

# shellcheck disable=SC1091
source ./create_resource.sh

[ -z "${QUAY_TOKEN}" ]
[ -z "${GITHUB_TOKEN}" ]
[ -z "${GITHUB_USER}" ]
[ -z "${GITHUB_REPO}" ]

export RHDH_NAMESPACE=${RHDH_NAMESPACE:-rhdh-performance}
export RHDH_HELM_RELEASE_NAME=${RHDH_HELM_RELEASE_NAME:-rhdh}

export RHDH_OPERATOR_NAMESPACE=rhdh-operator

cli="oc"
clin="$cli -n $RHDH_NAMESPACE"

repo_name="$RHDH_NAMESPACE-helm-repo"

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

export RHDH_HELM_REPO=${RHDH_HELM_REPO:-https://raw.githubusercontent.com/rhdh-bot/openshift-helm-charts/rhdh-1.2-rhel-9/installation}
export RHDH_HELM_CHART=${RHDH_HELM_CHART:-redhat-developer-hub}
export RHDH_HELM_CHART_VERSION=${RHDH_HELM_CHART_VERSION:-}

OCP_VER="$(oc version -o json | jq -r '.openshiftVersion' | sed -r -e "s#([0-9]+\.[0-9]+)\..+#\1#")"
OCP_ARCH="$(oc version -o json | jq -r '.serverVersion.platform' | sed -r -e "s#linux/##" | sed -e 's#amd64#x86_64#')"
export RHDH_OLM_INDEX_IMAGE="${RHDH_OLM_INDEX_IMAGE:-quay.io/rhdh/iib:1.2-v${OCP_VER}-${OCP_ARCH}}"
export RHDH_OLM_CHANNEL=${RHDH_OLM_CHANNEL:-fast}
export RHDH_OLM_OPERATOR_PACKAGE=${RHDH_OLM_OPERATOR_PACKAGE:-rhdh}

export PRE_LOAD_DB="${PRE_LOAD_DB:-true}"
export BACKSTAGE_USER_COUNT="${BACKSTAGE_USER_COUNT:-1}"
export GROUP_COUNT="${GROUP_COUNT:-1}"
export API_COUNT="${API_COUNT:-1}"
export COMPONENT_COUNT="${COMPONENT_COUNT:-1}"
export KEYCLOAK_USER_PASS=${KEYCLOAK_USER_PASS:-$(mktemp -u XXXXXXXXXX)}
export AUTH_PROVIDER="${AUTH_PROVIDER:-''}"
export ENABLE_RBAC="${ENABLE_RBAC:-false}"
export ENABLE_PROFILING="${ENABLE_PROFILING:-false}"

export PSQL_LOG="${PSQL_LOG:-true}"
export RHDH_METRIC="${RHDH_METRIC:-true}"
export LOG_MIN_DURATION_STATEMENT="${LOG_MIN_DURATION_STATEMENT:-65}"
export LOG_MIN_DURATION_SAMPLE="${LOG_MIN_DURATION_SAMPLE:-50}"
export LOG_STATEMENT_SAMPLE_RATE="${LOG_STATEMENT_SAMPLE_RATE:-0.7}"

export INSTALL_METHOD=helm

TMP_DIR=$(readlink -m "${TMP_DIR:-.tmp}")
mkdir -p "${TMP_DIR}"

wait_to_start_in_namespace() {
    namespace=${1:-${RHDH_NAMESPACE}}
    resource=${2:-deployment}
    name=${3:-name}
    initial_timeout=${4:-300}
    wait_timeout=${5:-300}
    rn=$resource/$name
    description=${6:-$rn}
    timeout_timestamp=$(date -d "$initial_timeout seconds" "+%s")
    interval=10s
    while ! /bin/bash -c "$cli -n $namespace get $rn -o name"; do
        if [ "$(date "+%s")" -gt "$timeout_timestamp" ]; then
            echo "[ERROR][$(date --utc -Ins)] Timeout waiting for $description to start"
            exit 1
        else
            echo "[INFO][$(date --utc -Ins)] Waiting $interval for $description to start..."
            sleep "$interval"
        fi
    done
    $cli -n "$namespace" rollout status "$rn" --timeout="${wait_timeout}s"
}

wait_for_crd() {
    name=${1:-name}
    initial_timeout=${2:-300}
    rn=crd/$name
    description=${3:-$rn}
    timeout_timestamp=$(date -d "$initial_timeout seconds" "+%s")
    interval=10s
    while ! /bin/bash -c "$cli get $rn"; do
        if [ "$(date "+%s")" -gt "$timeout_timestamp" ]; then
            echo "[ERROR][$(date --utc -Ins)] Timeout waiting for $description to exist"
            exit 1
        else
            echo "[INFO][$(date --utc -Ins)] Waiting $interval for $description to exist..."
            sleep "$interval"
        fi
    done
}

wait_to_start() {
    wait_to_start_in_namespace "$RHDH_NAMESPACE" "$@"
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
    appurl=$(oc whoami --show-console)
    export OPENSHIFT_APP_DOMAIN=${appurl#*.}
    $cli create namespace "${RHDH_NAMESPACE}" --dry-run=client -o yaml | $cli apply -f -
    keycloak_install

    if $PRE_LOAD_DB; then
        create_groups
        create_users
    fi

    backstage_install
    psql_debug
    setup_monitoring
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
    grep -m 1 "rhsso-operator" <($clin get pods -w)
    wait_to_start deployment rhsso-operator 300 300
    envsubst <template/keycloak/keycloak.yaml | $clin apply -f -
    wait_to_start statefulset keycloak 450 600
    envsubst <template/keycloak/keycloakRealm.yaml | $clin apply -f -
    envsubst <template/keycloak/keycloakClient.yaml | $clin apply -f -
    envsubst <template/keycloak/keycloakUser.yaml | $clin apply -f -
}

create_objs() {
    if ! $PRE_LOAD_DB; then
        create_groups
        create_users
    fi

    if [[ ${GITHUB_USER} ]] && [[ ${GITHUB_REPO} ]]; then
        create_per_grp create_cmp COMPONENT_COUNT
        create_per_grp create_api API_COUNT
    else
        echo "skipping component creating. GITHUB_REPO and GITHUB_USER not set"
        exit 1
    fi
}

backstage_install() {
    echo "Installing RHDH with install method: $INSTALL_METHOD"
    cp "template/backstage/app-config.yaml" "$TMP_DIR/app-config.yaml"
    if [ "${AUTH_PROVIDER}" == "keycloak" ]; then yq -i '. |= . + {"signInPage":"oauth2Proxy"}' "$TMP_DIR/app-config.yaml"; fi
    if [ "${AUTH_PROVIDER}" == "keycloak" ]; then yq -i '. |= . + {"auth":{"environment":"production","providers":{"oauth2Proxy":{}}}}' "$TMP_DIR/app-config.yaml"; else yq -i '. |= . + {"auth":{"providers":{"guest":{"dangerouslyAllowOutsideDevelopment":true}}}}' "$TMP_DIR/app-config.yaml"; fi
    until envsubst <template/backstage/secret-rhdh-pull-secret.yaml | $clin apply -f -; do $clin delete secret rhdh-pull-secret --ignore-not-found=true; done
    if ${ENABLE_RBAC}; then yq -i '. |= . + load("template/backstage/'$INSTALL_METHOD'/app-rbac-patch.yaml")' "$TMP_DIR/app-config.yaml"; fi
    until $clin create configmap app-config-rhdh --from-file "app-config.rhdh.yaml=$TMP_DIR/app-config.yaml"; do $clin delete configmap app-config-rhdh --ignore-not-found=true; done
    if ${ENABLE_RBAC}; then
        cp template/backstage/rbac-config.yaml "${TMP_DIR}"
        cat "$TMP_DIR/group-rbac.yaml" >>"$TMP_DIR/rbac-config.yaml"
        $clin apply -f "$TMP_DIR/rbac-config.yaml" --namespace="${RHDH_NAMESPACE}"
    fi
    envsubst <template/backstage/plugin-secrets.yaml | $clin apply -f -
    if [ "$INSTALL_METHOD" == "helm" ]; then
        install_rhdh_with_helm
    elif [ "$INSTALL_METHOD" == "olm" ]; then
        install_rhdh_with_olm
    else
        echo "Invalid install method: $INSTALL_METHOD, currently allowed methods are helm or olm"
        return 1
    fi
    if [ "${AUTH_PROVIDER}" == "keycloak" ] && ${RHDH_METRIC}; then $clin create -f template/backstage/rhdh-metrics-service.yaml; fi
    if ${RHDH_METRIC}; then envsubst <template/backstage/rhdh-servicemonitor.yaml| $clin create -f -; fi
}

# shellcheck disable=SC2016,SC1004
install_rhdh_with_helm() {
    helm repo remove "${repo_name}" || true
    helm repo add "${repo_name}" "${RHDH_HELM_REPO}"
    helm repo update "${repo_name}"
    chart_values=template/backstage/helm/chart-values.yaml
    if [ -n "${RHDH_IMAGE_REGISTRY}${RHDH_IMAGE_REPO}${RHDH_IMAGE_TAG}" ]; then
        echo "Using '$RHDH_IMAGE_REGISTRY/$RHDH_IMAGE_REPO:$RHDH_IMAGE_TAG' image for RHDH"
        chart_values=template/backstage/helm/chart-values.image-override.yaml
    fi
    version_arg=""
    chart_origin=$repo_name/$RHDH_HELM_CHART
    if [ -n "${RHDH_HELM_CHART_VERSION}" ]; then
        version_arg="--version $RHDH_HELM_CHART_VERSION"
        chart_origin="$chart_origin@$RHDH_HELM_CHART_VERSION"
    fi
    echo "Installing RHDH Helm chart $RHDH_HELM_RELEASE_NAME from $chart_origin in $RHDH_NAMESPACE namespace"
    cp "$chart_values" "$TMP_DIR/chart-values.temp.yaml"
    if [ "${AUTH_PROVIDER}" == "keycloak" ]; then yq -i '.upstream.backstage |= . + load("template/backstage/helm/oauth2-container-patch.yaml")' "$TMP_DIR/chart-values.temp.yaml"; fi
    if ${ENABLE_RBAC}; then
        if helm search repo --devel -r rhdh --version 1.2-1 --fail-on-no-result; then
            yq -i '.upstream.backstage |= . + load("template/backstage/helm/extravolume-patch-1.2.yaml")' "$TMP_DIR/chart-values.temp.yaml"
        else
            yq -i '.upstream.backstage |= . + load("template/backstage/helm/extravolume-patch-1.1.yaml")' "$TMP_DIR/chart-values.temp.yaml"
        fi
        yq -i '.global.dynamic.plugins |= . + load("template/backstage/helm/rbac-plugin-patch.yaml")' "$TMP_DIR/chart-values.temp.yaml"
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
    helm upgrade --install "${RHDH_HELM_RELEASE_NAME}" --devel "${repo_name}/${RHDH_HELM_CHART}" ${version_arg} -n "${RHDH_NAMESPACE}" --values "$TMP_DIR/chart-values.yaml"
    wait_to_start statefulset "${RHDH_HELM_RELEASE_NAME}-postgresql-read" 300 300
    wait_to_start deployment "${RHDH_HELM_RELEASE_NAME}-developer-hub" 300 300
}

install_rhdh_with_olm() {
    $clin create secret generic rhdh-backend-secret --from-literal=BACKEND_SECRET="$(mktemp -u XXXXXXXXXXX)"
    mark_resource_for_rhdh secret rhdh-backend-secret
    $clin create cm app-config-backend-secret --from-file=template/backstage/olm/app-config.rhdh.backend-secret.yaml
    mark_resource_for_rhdh cm app-config-backend-secret
    $clin apply -f template/backstage/olm/dynamic-plugins.configmap.yaml
    mark_resource_for_rhdh cm dynamic-plugins-rhdh
    set -x
    OLM_CHANNEL="${RHDH_OLM_CHANNEL}" UPSTREAM_IIB="${RHDH_OLM_INDEX_IMAGE}" ./install-rhdh-catalog-source.sh --install-operator "${RHDH_OLM_OPERATOR_PACKAGE:-rhdh}"
    set +x
    wait_for_crd backstages.rhdh.redhat.com

    backstage_yaml="$TMP_DIR/backstage.yaml"
    envsubst <template/backstage/olm/backstage.yaml >"$backstage_yaml"
    if ${ENABLE_RBAC}; then
        rbac_policy='[{"name": "rbac-policy"}]'
        yq -i '(.spec.application.extraFiles.configMaps |= (. // []) + '"$rbac_policy" "$backstage_yaml"
    fi
    $clin apply -f "$backstage_yaml"

    wait_to_start statefulset "backstage-psql-developer-hub" 300 300
    wait_to_start deployment "backstage-developer-hub" 300 300
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
        $clin exec "${psql_db}" -- sh -c "sed -i "s/^\s*#log_min_duration_statement.*/log_min_duration_statement=${LOG_MIN_DURATION_STATEMENT}/" /var/lib/pgsql/data/userdata/postgresql.conf "
        $clin exec "${psql_db}" -- sh -c "sed -i "s/^\s*#log_min_duration_sample.*/log_min_duration_sample=${LOG_MIN_DURATION_SAMPLE}/" /var/lib/pgsql/data/userdata/postgresql.conf "
        $clin exec "${psql_db}" -- sh -c "sed -i "s/^\s*#log_statement_sample_rate.*/log_statement_sample_rate=${LOG_STATEMENT_SAMPLE_RATE}/" /var/lib/pgsql/data/userdata/postgresql.conf "
    fi
    echo "Restarting RHDH DB..."
    $clin rollout restart statefulset/"$psql_db_ss"
    wait_to_start statefulset "$psql_db_ss" 300 300

    echo "Restarting RHDH..."
    $clin rollout restart deployment/"$rhdh_deployment"
    wait_to_start deployment "$rhdh_deployment" 300 300
}
setup_monitoring() {
    echo "Enabling user workload monitoring"
    rm -f config.yaml
    if oc -n openshift-monitoring get cm cluster-monitoring-config; then
        oc -n openshift-monitoring extract configmap/cluster-monitoring-config --to=. --keys=config.yaml
        sed -i '/^enableUserWorkload:/d' config.yaml
        echo -e "\nenableUserWorkload: true" >>config.yaml
        oc -n openshift-monitoring set data configmap/cluster-monitoring-config --from-file=config.yaml
    else
        cat <<EOD >config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-monitoring-config
  namespace: openshift-monitoring
data:
  config.yaml: |
    enableUserWorkload: true
EOD
        oc -n openshift-monitoring apply -f config.yaml
    fi
    before=$(date --utc +%s)
    while true; do
        count=$(kubectl -n "openshift-user-workload-monitoring" get StatefulSet -l operator.prometheus.io/name=user-workload -o name 2>/dev/null | wc -l)
        [ "$count" -gt 0 ] && break
        now=$(date --utc +%s)
        if [[ $((now - before)) -ge "300" ]]; then
            echo "Required StatefulSet did not appeared before timeout"
            exit 1
        fi
        sleep 3
    done

    kubectl -n openshift-user-workload-monitoring rollout status --watch --timeout=600s StatefulSet/prometheus-user-workload
    kubectl -n openshift-user-workload-monitoring wait --for=condition=ready pod -l app.kubernetes.io/component=prometheus
    kubectl -n openshift-user-workload-monitoring get pod

    echo "Setup monitoring"
    cat <<EOF | kubectl -n locust-operator apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  labels:
    app: locust-operator
  annotations:
    networkoperator.openshift.io/ignore-errors: ""
  name: locust-operator-monitor
  namespace: locust-operator
spec:
  endpoints:
    - interval: 10s
      port: prometheus-metrics
      honorLabels: true
  jobLabel: app
  namespaceSelector:
    matchNames:
      - locust-operator
  selector: {}
EOF
}

delete() {
    echo "Remove RHDH with install method: $INSTALL_METHOD"
    if ! $cli get ns "$RHDH_NAMESPACE" >/dev/null; then
        echo "$RHDH_NAMESPACE namespace does not exit... Skipping. "
    else
        for cr in keycloakusers keycloakclients keycloakrealms keycloaks; do
            for res in $($clin get "$cr.keycloak.org" -o name); do
                $clin patch "$res" -p '{"metadata":{"finalizers":[]}}' --type=merge
                $clin delete "$res" --wait
            done
        done
    fi
    if [ "$INSTALL_METHOD" == "helm" ]; then
        helm uninstall "${RHDH_HELM_RELEASE_NAME}" --namespace "${RHDH_NAMESPACE}"
        $clin delete pvc "data-${RHDH_HELM_RELEASE_NAME}-postgresql-0" --ignore-not-found=true
        $cli delete ns "${RHDH_NAMESPACE}" --ignore-not-found=true --wait
        helm repo remove "${repo_name}" || true
    elif [ "$INSTALL_METHOD" == "olm" ]; then
        delete_rhdh_with_olm
    fi
}

delete_rhdh_with_olm() {
    $clin delete backstage developer-hub --ignore-not-found=true --wait
    $cli delete namespace "$RHDH_NAMESPACE" --ignore-not-found=true --wait

    $cli -n "$RHDH_OPERATOR_NAMESPACE" delete sub rhdh --ignore-not-found=true --wait
    for i in $($cli get catsrc -n openshift-marketplace -o json | jq -rc '.items[] | select(.metadata.name | startswith("rhdh")).metadata.name'); do
        $cli -n openshift-marketplace delete catsrc "$i" --ignore-not-found=true --wait
    done
    $cli delete namespace "$RHDH_OPERATOR_NAMESPACE" --ignore-not-found=true --wait
}

while getopts "oi:crd" flag; do
    case "${flag}" in
    o)
        export INSTALL_METHOD=olm
        ;;
    c)
        create_objs
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
    \?)
        echo "WARNING: Invalid option: ${flag} - defaulting to -i (install)"
        install
        ;;
    esac
done
