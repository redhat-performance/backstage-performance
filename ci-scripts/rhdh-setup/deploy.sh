#!/bin/bash
set -uo pipefail

source ./create_resource.sh

[ -z ${QUAY_TOKEN} ]
[ -z ${GITHUB_TOKEN} ]
[ -z ${GITHUB_USER} ]
[ -z ${GITHUB_REPO} ]

export RHDH_NAMESPACE=${RHDH_NAMESPACE:-rhdh-performance}
export RHDH_HELM_RELEASE_NAME=${RHDH_HELM_RELEASE_NAME:-rhdh}

cli="oc"
clin="$cli -n $RHDH_NAMESPACE"

export RHDH_DEPLOYMENT_REPLICAS=${RHDH_DEPLOYMENT_REPLICAS:-1}
export RHDH_DB_REPLICAS=${RHDH_DB_REPLICAS:-1}
export RHDH_KEYCLOAK_REPLICAS=${RHDH_KEYCLOAK_REPLICAS:-1}

export RHDH_IMAGE_REGISTRY=${RHDH_IMAGE_REGISTRY:-quay.io}
export RHDH_IMAGE_REPO=${RHDH_IMAGE_REPO:-rhdh/rhdh-hub-rhel9}
export RHDH_IMAGE_TAG=${RHDH_IMAGE_TAG:-1.0-162}

export RHDH_HELM_REPO=${RHDH_HELM_REPO:-https://gist.githubusercontent.com/nickboldt/a8483eb244f9c4286798e85accaa70af/raw} #v1.0-162
export RHDH_HELM_CHART=${RHDH_HELM_CHART:-developer-hub}

export PRE_LOAD_DB="${PRE_LOAD_DB:-true}"
export BACKSTAGE_USER_COUNT="${BACKSTAGE_USER_COUNT:-1}"
export GROUP_COUNT="${GROUP_COUNT:-1}"
export API_COUNT="${API_COUNT:-1}"
export COMPONENT_COUNT="${COMPONENT_COUNT:-1}"

delete() {
    for cr in keycloakusers keycloakclients keycloakrealms keycloaks; do
        for res in $($clin get $cr.keycloak.org -o name); do
            $clin patch $res -p '{"metadata":{"finalizers":[]}}' --type=merge
            $clin delete $res --wait
        done
    done
    helm uninstall ${RHDH_HELM_RELEASE_NAME} --namespace ${RHDH_NAMESPACE}
    $clin delete pvc data-${RHDH_HELM_RELEASE_NAME}-postgresql-0 --ignore-not-found
    $cli delete ns ${RHDH_NAMESPACE} --wait
}

keycloak_install() {
    $cli create namespace ${RHDH_NAMESPACE} --dry-run=client -o yaml | $cli apply -f -
    export KEYCLOAK_CLIENT_SECRET=$(mktemp -u XXXXXXXXXX)
    cat template/keycloak/keycloak-op.yaml | envsubst | $clin apply -f -
    grep -m 1 "rhsso-operator" <($clin get pods -w)
    $clin wait --for=condition=Ready pod -l=name=rhsso-operator --timeout=300s
    cat template/keycloak/keycloak.yaml | envsubst | $clin apply -f -
    timeout=$(date -d "450 seconds" "+%s")
    while ! /bin/bash -c "$clin get statefulset/keycloak -o name"; do
        if [ "$(date "+%s")" -gt "$timeout" ]; then
            echo "ERROR: Timeout waiting for keycloak to start"
            exit 1
        else
            echo "Waiting for keycloak to start..."
            sleep 5s
        fi
    done
    $clin rollout status statefulset/keycloak --timeout=600s
    cat template/keycloak/keycloakRealm.yaml | envsubst | $clin apply -f -
    cat template/keycloak/keycloakClient.yaml | envsubst | $clin apply -f -
    cat template/keycloak/keycloakUser.yaml | envsubst | $clin apply -f -
}

backstage_install() {
    until cat template/backstage/secret-rhdh-pull-secret.yaml | envsubst | $clin apply -f -; do $clin delete secret rhdh-pull-secret; done
    cat template/backstage/app-config.yaml | envsubst '${RHDH_NAMESPACE} ${OPENSHIFT_APP_DOMAIN}' >app-config.yaml
    until $clin create configmap app-config-rhdh --from-file "app-config-rhdh.yaml=app-config.yaml"; do $clin delete configmap app-config-rhdh; done
    cat template/backstage/plugin-secrets.yaml | envsubst | $clin apply -f -
    helm repo add rhdh-helm-repo ${RHDH_HELM_REPO}
    helm repo update rhdh-helm-repo
    cat template/backstage/chart-values.yaml |
        envsubst \
            '${OPENSHIFT_APP_DOMAIN} \
            ${RHDH_HELM_RELEASE_NAME} \
            ${RHDH_DEPLOYMENT_REPLICAS} \
            ${RHDH_DB_REPLICAS} \
            ${RHDH_IMAGE_REGISTRY} \
            ${RHDH_IMAGE_REPO} \
            ${RHDH_IMAGE_TAG} \
            ' | helm upgrade --install ${RHDH_HELM_RELEASE_NAME} --devel rhdh-helm-repo/${RHDH_HELM_CHART} -n ${RHDH_NAMESPACE} --values -
    $clin rollout status deployment/${RHDH_HELM_RELEASE_NAME}-developer-hub --timeout=300s
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

    if [[ ${GITHUB_USER}  ]] && [[ ${GITHUB_REPO} ]] ; then
      create_per_grp create_cmp COMPONENT_COUNT
      [[ $? -eq 0 ]] && clone_and_upload component.yaml

      create_per_grp create_api API_COUNT
      [[ $? -eq 0 ]] && clone_and_upload api.yaml
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

while getopts "rd" flag; do
    case "${flag}" in
    r)
        delete
        ;;
    d)
        delete
        exit 0
        ;;
    *)
        echo "Invalid option: ${flag}"
        ;;
    esac
done

install
create_objs
