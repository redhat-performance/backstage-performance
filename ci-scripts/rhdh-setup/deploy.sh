#!/bin/bash
set -uo pipefail

# shellcheck disable=SC1091
source ./create_resource.sh

[ -z "${QUAY_TOKEN}" ]
[ -z "${GITHUB_TOKEN}" ]
[ -z "${GITHUB_USER}" ]
[ -z "${GITHUB_REPO}" ]

export RHDH_NAMESPACE=${RHDH_NAMESPACE:-rhdh-performance}
export RHDH_HELM_RELEASE_NAME=${RHDH_HELM_RELEASE_NAME:-rhdh}

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

export RHDH_HELM_REPO=${RHDH_HELM_REPO:-https://raw.githubusercontent.com/rhdh-bot/openshift-helm-charts/rhdh-1.1-rhel-9/installation}
export RHDH_HELM_CHART=${RHDH_HELM_CHART:-developer-hub}
export RHDH_HELM_CHART_VERSION=${RHDH_HELM_CHART_VERSION:-}

export PRE_LOAD_DB="${PRE_LOAD_DB:-true}"
export BACKSTAGE_USER_COUNT="${BACKSTAGE_USER_COUNT:-1}"
export GROUP_COUNT="${GROUP_COUNT:-1}"
export API_COUNT="${API_COUNT:-1}"
export COMPONENT_COUNT="${COMPONENT_COUNT:-1}"
export KEYCLOAK_USER_PASS=${KEYCLOAK_USER_PASS:-$(mktemp -u XXXXXXXXXX)}
export AUTH_PROVIDER="${AUTH_PROVIDER:-''}"


TMP_DIR=$(readlink -m "${TMP_DIR:-.tmp}")
mkdir -p "${TMP_DIR}"

wait_to_start() {
    resource=${1:-deployment}
    name=${2:-name}
    initial_timeout=${3:-300}
    wait_timeout=${4:-300}
    rn=$resource/$name
    description=${5:-$rn}
    timeout_timestamp=$(date -d "$initial_timeout seconds" "+%s")
    interval=10s
    while ! /bin/bash -c "$clin get $rn -o name"; do
        if [ "$(date "+%s")" -gt "$timeout_timestamp" ]; then
            echo "[ERROR][$(date --utc -Ins)] Timeout waiting for $description to start"
            exit 1
        else
            echo "[INFO][$(date --utc -Ins)] Waiting $interval for $description to start..."
            sleep "$interval"
        fi
    done
    $clin rollout status "$rn" --timeout="${wait_timeout}s"
}

delete() {
    if ! $cli get ns "$RHDH_NAMESPACE" >/dev/null; then
        echo "$RHDH_NAMESPACE namespace does not exit... Skipping. "
        return
    fi
    for cr in keycloakusers keycloakclients keycloakrealms keycloaks; do
        for res in $($clin get "$cr.keycloak.org" -o name); do
            $clin patch "$res" -p '{"metadata":{"finalizers":[]}}' --type=merge
            $clin delete "$res" --wait
        done
    done
    helm uninstall "${RHDH_HELM_RELEASE_NAME}" --namespace "${RHDH_NAMESPACE}"
    $clin delete pvc "data-${RHDH_HELM_RELEASE_NAME}-postgresql-0" --ignore-not-found
    $cli delete ns "${RHDH_NAMESPACE}" --wait
    helm repo remove "${repo_name}" || true
}

keycloak_install() {
    $cli create namespace "${RHDH_NAMESPACE}" --dry-run=client -o yaml | $cli apply -f -
    export KEYCLOAK_CLIENT_SECRET
    export COOKIE_SECRET
    KEYCLOAK_CLIENT_SECRET=$(mktemp -u XXXXXXXXXX)
    COOKIE_SECRET=$(dd if=/dev/urandom bs=32 count=1 2>/dev/null | base64 | tr -d -- '\n' | tr -- '+/' '-_'; echo)
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

# shellcheck disable=SC2016,SC1004
backstage_install() {
    cp "template/backstage/app-config.yaml" "$TMP_DIR/app-config.yaml"
    if [ "${AUTH_PROVIDER}" == "keycloak" ]; then yq -i '. |= . + {"signInPage":"oauth2Proxy"}' "$TMP_DIR/app-config.yaml"; fi
    if [ "${AUTH_PROVIDER}" == "keycloak" ]; then yq -i '. |= . + {"auth":{"environment":"production","providers":{"oauth2Proxy":{}}}}' "$TMP_DIR/app-config.yaml"; fi
    until envsubst <template/backstage/secret-rhdh-pull-secret.yaml | $clin apply -f -; do $clin delete secret rhdh-pull-secret; done
    until $clin create configmap app-config-rhdh --from-file "app-config-rhdh.yaml=$TMP_DIR/app-config.yaml"; do $clin delete configmap app-config-rhdh; done
    envsubst <template/backstage/plugin-secrets.yaml | $clin apply -f -
    helm repo remove "${repo_name}" || true
    helm repo add "${repo_name}" "${RHDH_HELM_REPO}"
    helm repo update "${repo_name}"
    chart_values=template/backstage/chart-values.yaml
    if [ -n "${RHDH_IMAGE_REGISTRY}${RHDH_IMAGE_REPO}${RHDH_IMAGE_TAG}" ]; then
        echo "Using '$RHDH_IMAGE_REGISTRY/$RHDH_IMAGE_REPO:$RHDH_IMAGE_TAG' image for RHDH"
        chart_values=template/backstage/chart-values.image-override.yaml
    fi
    version_arg=""
    chart_origin=$repo_name/$RHDH_HELM_CHART
    if [ -n "${RHDH_HELM_CHART_VERSION}" ]; then
        version_arg="--version $RHDH_HELM_CHART_VERSION"
        chart_origin="$chart_origin@$RHDH_HELM_CHART_VERSION"
    fi
    echo "Installing RHDH Helm chart $RHDH_HELM_RELEASE_NAME from $chart_origin in $RHDH_NAMESPACE namespace"
    cp "$chart_values" "$TMP_DIR/chart-values.temp.yaml"
    if [ "${AUTH_PROVIDER}" == "keycloak" ]; then yq -i '.upstream.backstage |= . + load("template/backstage/oauth2-container-patch.yaml")' "$TMP_DIR/chart-values.temp.yaml"; fi
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
        ${COOKIE_SECRET} \
        ' <"$TMP_DIR/chart-values.temp.yaml" >"$TMP_DIR/chart-values.yaml"
    if [ -n "${RHDH_RESOURCES_CPU_REQUESTS}" ]; then yq -i '.upstream.backstage.resources.requests.cpu = "'"${RHDH_RESOURCES_CPU_REQUESTS}"'"' "$TMP_DIR/chart-values.yaml"; fi
    if [ -n "${RHDH_RESOURCES_CPU_LIMITS}" ]; then yq -i '.upstream.backstage.resources.limits.cpu = "'"${RHDH_RESOURCES_CPU_LIMITS}"'"' "$TMP_DIR/chart-values.yaml"; fi
    if [ -n "${RHDH_RESOURCES_MEMORY_REQUESTS}" ]; then yq -i '.upstream.backstage.resources.requests.memory = "'"${RHDH_RESOURCES_MEMORY_REQUESTS}"'"' "$TMP_DIR/chart-values.yaml"; fi
    if [ -n "${RHDH_RESOURCES_MEMORY_LIMITS}" ]; then yq -i '.upstream.backstage.resources.limits.memory = "'"${RHDH_RESOURCES_MEMORY_LIMITS}"'"' "$TMP_DIR/chart-values.yaml"; fi
    if [ "${AUTH_PROVIDER}" == "keycloak" ]; then yq -i '.upstream.service.ports.targetPort = "oauth2-proxy"' "$TMP_DIR/chart-values.yaml"; fi
    if [ "${AUTH_PROVIDER}" == "keycloak" ]; then yq -i '.upstream.service.ports.backend = 4180' "$TMP_DIR/chart-values.yaml"; fi
    #shellcheck disable=SC2086
    helm upgrade --install "${RHDH_HELM_RELEASE_NAME}" --devel "${repo_name}/${RHDH_HELM_CHART}" ${version_arg} -n "${RHDH_NAMESPACE}" --values "$TMP_DIR/chart-values.yaml"
    wait_to_start statefulset "${RHDH_HELM_RELEASE_NAME}-postgresql-read" 300 300
    wait_to_start deployment "${RHDH_HELM_RELEASE_NAME}-developer-hub" 300 300
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
    cat config.yaml
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

create_objs() {
    if ! $PRE_LOAD_DB; then
        create_groups
        create_users
    fi

    if [[ ${GITHUB_USER} ]] && [[ ${GITHUB_REPO} ]]; then
        if create_per_grp create_cmp COMPONENT_COUNT; then
            clone_and_upload "component-*.yaml"
        fi

        if create_per_grp create_api API_COUNT; then
            clone_and_upload "api-*.yaml"
        fi
    else
        echo "skipping component creating. GITHUB_REPO and GITHUB_USER not set"
        exit 1
    fi
}

install() {
    appurl=$(oc whoami --show-console)
    export OPENSHIFT_APP_DOMAIN=${appurl#*.}
    keycloak_install

    if $PRE_LOAD_DB; then
        create_groups
        create_users
    fi

    backstage_install
    setup_monitoring
}

while getopts ":i:crd" flag; do
    case "${flag}" in
    c)
        create_objs
	exit 0
        ;;
    r)
        delete
        install
	exit 0
        ;;
    d)
        delete
	exit 0
        ;;
    i)
        AUTH_PROVIDER="$OPTARG"
        install
	exit 0
        ;;
    \?)
        echo "WARNING: Invalid option: ${flag} - defaulting to -i (install)"
        ;;
    esac
done

install
