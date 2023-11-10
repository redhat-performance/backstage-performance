#!/bin/bash
set -uo pipefail
[ -z ${QUAY_TOKEN} ]
[ -z ${GITHUB_TOKEN} ]

export NAMESPACE=rhdh-performance
export JANUS_HELM_CHART=rhdh

cli="oc"
clin="$cli -n $NAMESPACE"

delete() {
    for cr in keycloakusers keycloakclients keycloakrealms keycloaks; do
        for res in $($clin get $cr.keycloak.org -o name); do
            $clin patch $res -p '{"metadata":{"finalizers":[]}}' --type=merge
            $clin delete $res --wait
        done
    done
    helm uninstall ${JANUS_HELM_CHART} --namespace ${NAMESPACE}
    $clin delete pvc data-${JANUS_HELM_CHART}-postgresql-0 --ignore-not-found
    $cli delete ns ${NAMESPACE} --wait
}

keycloak_install() {
    $cli create namespace ${NAMESPACE} --dry-run=client -o yaml | $cli apply -f -
    export KEYCLOAK_CLIENT_SECRET=$(mktemp -u XXXXXXXXXX)
    cat template/keycloak/keycloak-op.yaml | envsubst | $clin apply -f -
    grep -m 1 "rhsso-operator" <($clin get pods -w)
    $clin wait --for=condition=Ready pod -l=name=rhsso-operator --timeout=300s
    cat template/keycloak/keycloak.yaml | envsubst | $clin apply -f -
    grep -m 1 "keycloak-0" <($clin get pods -w)
    $clin wait --for=condition=Ready pod/keycloak-0 --timeout=300s
    cat template/keycloak/keycloakRealm.yaml | envsubst | $clin apply -f -
    cat template/keycloak/keycloakClient.yaml | envsubst | $clin apply -f -
    cat template/keycloak/keycloakUser.yaml | envsubst | $clin apply -f -
}

backstage_install() {
    until cat template/backstage/secret-rhdh-pull-secret.yaml | envsubst | $clin apply -f -; do $clin delete secret rhdh-pull-secret; done
    cat template/backstage/app-config.yaml | envsubst >app-config.yaml
    until $clin create configmap app-config-rhdh --from-file "app-config-rhdh.yaml=app-config.yaml"; do $clin delete configmap app-config-rhdh; done
    helm repo add openshift-helm-charts https://charts.openshift.io/
    helm repo update openshift-helm-charts
    cat template/backstage/chart-values.yaml | envsubst '${OPENSHIFT_APP_DOMAIN}' | helm upgrade --install ${JANUS_HELM_CHART} openshift-helm-charts/redhat-developer-hub -n ${NAMESPACE} --values -
    grep -m 1 "${JANUS_HELM_CHART}-developer-hub" <($clin get pods -w)
    $clin wait --for=condition=Ready pod -l=app.kubernetes.io/name=developer-hub --timeout=300s
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

install() {
    appurl=$(oc whoami --show-console)
    export OPENSHIFT_APP_DOMAIN=${appurl#*.}
    keycloak_install
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
    esac
done

install
