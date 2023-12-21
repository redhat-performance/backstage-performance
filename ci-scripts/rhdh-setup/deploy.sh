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
export RHDH_KEYCLOAK_REPLICAS=${RHDH_KEYCLOAK_REPLICAS:-1}

export RHDH_IMAGE_REGISTRY=${RHDH_IMAGE_REGISTRY:-}
export RHDH_IMAGE_REPO=${RHDH_IMAGE_REPO:-}
export RHDH_IMAGE_TAG=${RHDH_IMAGE_TAG:-}

export RHDH_HELM_REPO=${RHDH_HELM_REPO:-https://gist.githubusercontent.com/rhdh-bot/63cef5cb6285889527bd6a67c0e1c2a9/raw}
export RHDH_HELM_CHART=${RHDH_HELM_CHART:-developer-hub}
export RHDH_HELM_CHART_VERSION=${RHDH_HELM_CHART_VERSION:-}

export PRE_LOAD_DB="${PRE_LOAD_DB:-true}"
export BACKSTAGE_USER_COUNT="${BACKSTAGE_USER_COUNT:-1}"
export GROUP_COUNT="${GROUP_COUNT:-1}"
export API_COUNT="${API_COUNT:-1}"
export COMPONENT_COUNT="${COMPONENT_COUNT:-1}"

wait_to_start() {
    resource=${1:-deployment}
    name=${2:-name}
    initial_timeout=${3:-300}
    wait_timeout=${4:-300}
    rn=$resource/$name
    description=${5:-$rn}
    timeout_timestamp=$(date -d "$initial_timeout seconds" "+%s")
    while ! /bin/bash -c "$clin get $rn -o name"; do
        if [ "$(date "+%s")" -gt "$timeout_timestamp" ]; then
            echo "ERROR: Timeout waiting for $description to start"
            exit 1
        else
            echo "Waiting for $description to start..."
            sleep 5s
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
    KEYCLOAK_CLIENT_SECRET=$(mktemp -u XXXXXXXXXX)
    envsubst <template/keycloak/keycloak-op.yaml | $clin apply -f -
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
    until envsubst <template/backstage/secret-rhdh-pull-secret.yaml | $clin apply -f -; do $clin delete secret rhdh-pull-secret; done
    envsubst '${RHDH_NAMESPACE} ${OPENSHIFT_APP_DOMAIN}' <template/backstage/app-config.yaml >app-config.yaml
    until $clin create configmap app-config-rhdh --from-file "app-config-rhdh.yaml=app-config.yaml"; do $clin delete configmap app-config-rhdh; done
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
    #shellcheck disable=SC2086
    envsubst \
        '${OPENSHIFT_APP_DOMAIN} \
        ${RHDH_HELM_RELEASE_NAME} \
        ${RHDH_DEPLOYMENT_REPLICAS} \
        ${RHDH_DB_REPLICAS} \
        ${RHDH_DB_STORAGE} \
        ${RHDH_IMAGE_REGISTRY} \
        ${RHDH_IMAGE_REPO} \
        ${RHDH_IMAGE_TAG} \
	${KEYCLOAK_CLIENT_SECRET} \
	${RHDH_NAMESPACE} \
        ' <"$chart_values" | tee "$TMP_DIR/chart-values.yaml" | helm upgrade --install "${RHDH_HELM_RELEASE_NAME}" --devel "${repo_name}/${RHDH_HELM_CHART}" ${version_arg} -n "${RHDH_NAMESPACE}" --values -
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
            clone_and_upload "$TMP_DIR/component.yaml"
        fi

        if create_per_grp create_api API_COUNT; then
            clone_and_upload "$TMP_DIR/api.yaml"
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

while getopts "crdi" flag; do
    case "${flag}" in
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
        install
        ;;
    *)
        echo "WARNING: Invalid option: ${flag} - defaulting to -i (install)"
        install
        ;;
    esac
done
