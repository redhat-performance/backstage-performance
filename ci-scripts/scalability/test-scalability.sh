#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1090,SC1091
source "$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$SCRIPT_DIR"/../../test.env)"

export PRE_LOAD_DB=${PRE_LOAD_DB:-true}
export RHDH_HELM_REPO=${RHDH_HELM_REPO:-https://raw.githubusercontent.com/rhdh-bot/openshift-helm-charts/refs/heads/redhat-developer-hub-1.5-147-CI/installation}
export RHDH_HELM_RELEASE_NAME=${RHDH_HELM_RELEASE_NAME:-rhdh}
export RHDH_HELM_CHART=${RHDH_HELM_CHART:-developer-hub}
export RHDH_NAMESPACE=${RHDH_NAMESPACE:-rhdh-performance}

export ALWAYS_CLEANUP=${ALWAYS_CLEANUP:-false}

export WAIT_FOR_SEARCH_INDEX=${WAIT_FOR_SEARCH_INDEX:-true}

export GITHUB_TOKEN GITHUB_USER GITHUB_REPO QUAY_TOKEN
GITHUB_TOKEN="$(cat /usr/local/ci-secrets/backstage-performance/github.token)"
GITHUB_USER="$(cat /usr/local/ci-secrets/backstage-performance/github.user)"
GITHUB_REPO="$(cat /usr/local/ci-secrets/backstage-performance/github.repo)"
QUAY_TOKEN="$(cat /usr/local/ci-secrets/backstage-performance/quay.token)"

# shellcheck disable=SC1090,SC1091
source "${PROJ_ROOT}"ci-scripts/rhdh-setup/create_resource.sh

read -ra workers <<<"${SCALE_WORKERS:-5}"

read -ra active_users_spawn_rate <<<"${SCALE_ACTIVE_USERS_SPAWN_RATES:-1:1 200:40}"

read -ra bs_users_groups <<<"${SCALE_BS_USERS_GROUPS:-1:1 10000:2500}"

read -ra rbac_policy_size <<<"${SCALE_RBAC_POLICY_SIZE:-10000}"

read -ra catalog_apis_components <<<"${SCALE_CATALOG_SIZES:-1:1 10000:10000}"

read -ra rhdh_replicas <<<"${SCALE_REPLICAS:-1:1}"

read -ra db_storages <<<"${SCALE_DB_STORAGES:-1Gi 2Gi}"

read -ra cpu_requests_limits <<<"${SCALE_CPU_REQUESTS_LIMITS:-:}"

read -ra memory_requests_limits <<<"${SCALE_MEMORY_REQUESTS_LIMITS:-:}"

if [ -n "${SCALE_COMBINED:-}" ]; then
    read -ra combined_entries <<<"${SCALE_COMBINED}"
    USE_COMBINED_MODE=true
    echo
    echo "////// RHDH scalability test (COMBINED MODE) //////"
    echo "SCALE_COMBINED is set - overriding inner loops (catalog, users/groups, active_users)"
    echo "Number of combined entries: ${#combined_entries[*]}"
    echo "Number of scalability matrix iterations: $((${#workers[*]} * ${#cpu_requests_limits[*]} * ${#memory_requests_limits[*]} * ${#rhdh_replicas[*]} * ${#db_storages[*]} * ${#rbac_policy_size[*]} * ${#combined_entries[*]}))"
    echo
else
    USE_COMBINED_MODE=false
    echo
    echo "////// RHDH scalability test (NESTED LOOPS MODE) //////"
    echo "Number of scalability matrix iterations: $((${#workers[*]} * ${#active_users_spawn_rate[*]} * ${#bs_users_groups[*]} * ${#catalog_apis_components[*]} * ${#rhdh_replicas[*]} * ${#db_storages[*]} * ${#cpu_requests_limits[*]} * ${#memory_requests_limits[*]} * ${#rbac_policy_size[*]}))"
    echo
fi

wait_for_indexing() {
    COOKIE="$TMP_DIR/cookie.jar"
    if [ "$INSTALL_METHOD" == "helm" ]; then
        rhdh_route="$(oc -n "${RHDH_NAMESPACE}" get routes -l app.kubernetes.io/instance="${RHDH_HELM_RELEASE_NAME}" -o jsonpath='{.items[0].metadata.name}')"
    else
        if [ "$AUTH_PROVIDER" == "keycloak" ]; then
            rhdh_route="rhdh"
        else
            rhdh_route="backstage-developer-hub"
        fi
    fi
    if [ "$WAIT_FOR_SEARCH_INDEX" == "true" ]; then
        BASE_HOST="https://$(oc get routes "${rhdh_route}" -n "${RHDH_NAMESPACE:-rhdh-performance}" -o jsonpath='{.spec.host}')"

        start=$(date +%s)
        timeout_timestamp=$(python3 -c "from datetime import datetime, timedelta; t_add=int(3600); print(int((datetime.now() + timedelta(seconds=t_add)).timestamp()))")
        while true; do
            echo "Waiting for the search indexing to finish..."
            if [ "$(date "+%s")" -gt "$timeout_timestamp" ]; then
                echo "ERROR: Timeout waiting"
                exit 1
            else
                ACCESS_TOKEN=$(get_token "rhdh")
                count="$(curl -sk "$BASE_HOST/api/search/query?term=&types%5B0%5D=software-catalog" --cookie "$COOKIE" --cookie-jar "$COOKIE" -H 'Authorization: Bearer '"$ACCESS_TOKEN" | jq -rc '.numberOfResults')"
                if [ "$count" != "null" ]; then
                    finish=$(date +%s)
                    echo "Search query returned non-empty set ($count) - indexing has finished in $((finish - start))s"
                    break
                fi
            fi
            sleep 10s
        done
    else
        echo "WAIT_FOR_SEARCH_INDEX is set to $WAIT_FOR_SEARCH_INDEX, skipping waiting for search indexing!"
    fi
}

run_test_iteration() {
    if [ "$ALWAYS_CLEANUP" != "false" ]; then
        perform_cleanup
    fi
    echo
    echo "/// Running the scalability test ///"
    echo
    set -x
    export SCENARIO=${SCENARIO:-search-catalog}
    export USERS="${au}"
    export DURATION=${DURATION:-5m}
    export SPAWN_RATE="${sr}"
    set +x
    make clean
    test_artifacts="$SCALABILITY_ARTIFACTS/$index/test/${counter}/${au}u"
    mkdir -p "$test_artifacts"
    wait_for_indexing 2>&1 | tee "$test_artifacts/before-test-search.log"
    ARTIFACT_DIR=$test_artifacts ./ci-scripts/test.sh 2>&1 | tee "$test_artifacts/test.log"
    ARTIFACT_DIR=$test_artifacts ./ci-scripts/collect-results.sh 2>&1 | tee "$test_artifacts/collect-results.log"
    jq ".metadata.scalability.iteration = ${counter}" "$test_artifacts/benchmark.json" >$$.json
    mv -vf $$.json "$test_artifacts/benchmark.json"
}


env_setup() {
    echo
    echo "/// Setting up RHDH for scalability test ///"
    echo
    set -x
    export RHDH_DEPLOYMENT_REPLICAS="$r"
    export RHDH_DB_REPLICAS="$dbr"
    export RHDH_DB_STORAGE="$s"
    export RHDH_RESOURCES_CPU_REQUESTS="$cr"
    export RHDH_RESOURCES_CPU_LIMITS="$cl"
    export RHDH_RESOURCES_MEMORY_REQUESTS="$mr"
    export RHDH_RESOURCES_MEMORY_LIMITS="$ml"
    export RHDH_KEYCLOAK_REPLICAS="${RHDH_KEYCLOAK_REPLICAS:-$r}"
    export BACKSTAGE_USER_COUNT=$bu
    export GROUP_COUNT=$bg
    export RBAC_POLICY_SIZE="$rbs"
    export WORKERS=$w
    export API_COUNT=$a
    export COMPONENT_COUNT=$c
    index="${r}r-${dbr}dbr-db_${s}-${bu}bu-${bg}bg-${rbs}rbs-${w}w-${cr}cr-${cl}cl-${mr}mr-${ml}ml-${a}a-${c}c"
    set +x
    oc login "$OPENSHIFT_API" -u "$OPENSHIFT_USERNAME" -p "$OPENSHIFT_PASSWORD" --insecure-skip-tls-verify=true
}

perform_cleanup() {
    make clean-local undeploy-rhdh
    setup_artifacts="$SCALABILITY_ARTIFACTS/$index/setup/${counter}"
    mkdir -p "$setup_artifacts"
    ARTIFACT_DIR=$setup_artifacts ./ci-scripts/setup.sh 2>&1 | tee "$setup_artifacts/setup.log"
    wait_for_indexing 2>&1 | tee "$setup_artifacts/after-setup-search.log"
}

standard_iteration() {
    for a_c in "${catalog_apis_components[@]}"; do
        IFS=":" read -ra tokens <<<"${a_c}"
        a="${tokens[0]}"                                       # apis
        [[ "${#tokens[@]}" == 1 ]] && c="" || c="${tokens[1]}" # components
        for bu_bg in "${bs_users_groups[@]}"; do
            IFS=":" read -ra tokens <<<"${bu_bg}"
            bu="${tokens[0]}"                                        # backstage users
            [[ "${#tokens[@]}" == 1 ]] && bg="" || bg="${tokens[1]}" # backstage groups
            env_setup
            if [ "$ALWAYS_CLEANUP" == "false" ]; then
                perform_cleanup
            fi
            for au_sr in "${active_users_spawn_rate[@]}"; do
                IFS=":" read -ra tokens <<<"${au_sr}"
                au=${tokens[0]}                                          # active users
                [[ "${#tokens[@]}" == 1 ]] && sr="" || sr="${tokens[1]}" # spawn rate
                run_test_iteration
                ((counter += 1))
            done
        done
    done
}
pushd ../../
ARTIFACT_DIR=$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "${ARTIFACT_DIR:-.artifacts}")
mkdir -p "${ARTIFACT_DIR}"

SCALABILITY_ARTIFACTS="$ARTIFACT_DIR/scalability"
rm -rvf "${SCALABILITY_ARTIFACTS}"
mkdir -p "${SCALABILITY_ARTIFACTS}"

counter=1
for w in "${workers[@]}"; do
    for cr_cl in "${cpu_requests_limits[@]}"; do
        IFS=":" read -ra tokens <<<"${cr_cl}"
        cr="${tokens[0]}"                                        # cpu requests
        [[ "${#tokens[@]}" == 1 ]] && cl="" || cl="${tokens[1]}" # cpu limits
        for mr_ml in "${memory_requests_limits[@]}"; do
            IFS=":" read -ra tokens <<<"${mr_ml}"
            mr="${tokens[0]}"                                        # memory requests
            [[ "${#tokens[@]}" == 1 ]] && ml="" || ml="${tokens[1]}" # memory limits
            for r_c in "${rhdh_replicas[@]}"; do
                IFS=":" read -ra tokens <<<"${r_c}"
                r="${tokens[0]}"                                           # scale replica
                [[ "${#tokens[@]}" == 1 ]] && dbr="" || dbr="${tokens[1]}" # db replica
                for s in "${db_storages[@]}"; do
                    for rbs in "${rbac_policy_size[@]}"; do
                        if [ "$USE_COMBINED_MODE" == "true" ]; then
                            for combined_entry in "${combined_entries[@]}"; do
                                IFS=":" read -ra tokens <<<"${combined_entry}"
                                if [ "${#tokens[@]}" -lt 6 ]; then
                                    echo "ERROR: Invalid entry '$combined_entry'. Expected format: active_users:spawn_rate:backstage_users:groups:apis:components"
                                    exit 1
                                fi
                                au="${tokens[0]}"  # active users
                                sr="${tokens[1]}"  # spawn rate
                                bu="${tokens[2]}"  # backstage users
                                bg="${tokens[3]}"  # groups
                                a="${tokens[4]}"   # apis
                                c="${tokens[5]}"   # components
                                env_setup
                                if [ "$ALWAYS_CLEANUP" == "false" ]; then
                                    perform_cleanup
                                fi
                                run_test_iteration
                                ((counter += 1))
                            done
                        else
                            standard_iteration
                        fi
                    done
                done
            done
        done
    done
done

popd || exit
