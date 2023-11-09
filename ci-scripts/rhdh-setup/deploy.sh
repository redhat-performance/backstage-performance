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
    $clin get secret credential-example-sso -o template --template='{{.data.ADMIN_PASSWORD}}' | base64 -d
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

install() {
    appurl=$(oc whoami --show-console)
    export OPENSHIFT_APP_DOMAIN=${appurl#*.}
    keycloak_install
    backstage_install
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
