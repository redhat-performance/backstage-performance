#!/bin/bash

export PRE_LOAD_DB=${PRE_LOAD_DB:-true}
export RHDH_HELM_REPO=${RHDH_HELM_REPO:-https://gist.githubusercontent.com/rhdh-bot/63cef5cb6285889527bd6a67c0e1c2a9/raw}
export RHDH_HELM_CHART=${RHDH_HELM_CHART:-developer-hub}
export RHDH_NAMESPACE=${RHDH_NAMESPACE:-rhdh-performance}

export WAIT_FOR_SEARCH_INDEX=${WAIT_FOR_SEARCH_INDEX:-true}

export GITHUB_TOKEN GITHUB_USER GITHUB_REPO QUAY_TOKEN
GITHUB_TOKEN="$(cat /usr/local/ci-secrets/backstage-performance/github.token)"
GITHUB_USER="$(cat /usr/local/ci-secrets/backstage-performance/github.user)"
GITHUB_REPO="$(cat /usr/local/ci-secrets/backstage-performance/github.repo)"
QUAY_TOKEN="$(cat /usr/local/ci-secrets/backstage-performance/quay.token)"

read -ra workers <<<"${SCALE_WORKERS:-5}"

read -ra active_users_spawn_rate <<<"${SCALE_ACTIVE_USERS_SPAWN_RATES:-1:1 200:40}"

read -ra bs_users_groups <<<"${SCALE_BS_USERS_GROUPS:-1:1 15000:5000}"

read -ra catalog_sizes <<<"${SCALE_CATALOG_SIZES:-1 10000}"

read -ra replicas <<<"${SCALE_REPLICAS:-5}"

read -ra db_storages <<<"${SCALE_DB_STORAGES:-1Gi 2Gi}"

read -ra cpu_requests_limits <<<"${SCALE_CPU_REQUESTS_LIMITS:-:}"

read -ra memory_requests_limits <<<"${SCALE_MEMORY_REQUESTS_LIMITS:-:}"

echo
echo "////// RHDH scalability test //////"
echo "Number of scalability matrix iterations: $((${#workers[*]} * ${#active_users_spawn_rate[*]} * ${#bs_users_groups[*]} * ${#catalog_sizes[*]} * ${#replicas[*]} * ${#db_storages[*]}))"
echo

wait_for_indexing() {
    if [ "$WAIT_FOR_SEARCH_INDEX" == "true" ]; then
        HOST="https://$(oc get routes rhdh-developer-hub -n "${RHDH_NAMESPACE:-rhdh-performance}" -o jsonpath='{.spec.host}')"

        start=$(date +%s)
        timeout_timestamp=$(date -d "3600 seconds" "+%s")
        while true; do
            echo "Waiting for the search indexing to finish..."
            if [ "$(date "+%s")" -gt "$timeout_timestamp" ]; then
                echo "ERROR: Timeout waiting"
                exit 1
            else
                count="$(curl -sk "$HOST/api/search/query?term=&types%5B0%5D=software-catalog" | jq -rc '.numberOfResults')"
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
pushd ../../
ARTIFACT_DIR=$(readlink -m "${ARTIFACT_DIR:-.artifacts}")
mkdir -p "${ARTIFACT_DIR}"

SCALABILITY_ARTIFACTS="$ARTIFACT_DIR/scalability"
rm -rvf "${SCALABILITY_ARTIFACTS}"
mkdir -p "${SCALABILITY_ARTIFACTS}"

for w in "${workers[@]}"; do
    for bu_bg in "${bs_users_groups[@]}"; do
        IFS=":" read -ra tokens <<<"${bu_bg}"
        bu="${tokens[0]}"
        bg="${tokens[1]}"
        for cr_cl in "${cpu_requests_limits[@]}"; do
            IFS=":" read -ra tokens <<<"${cr_cl}"
            cr="${tokens[0]}"
            cl="${tokens[1]}"
            for mr_ml in "${memory_requests_limits[@]}"; do
                IFS=":" read -ra tokens <<<"${mr_ml}"
                mr="${tokens[0]}"
                ml="${tokens[1]}"
                for c in "${catalog_sizes[@]}"; do
                    for r in "${replicas[@]}"; do
                        for s in "${db_storages[@]}"; do
                            echo
                            echo "/// Setting up RHDH for scalability test ///"
                            echo
                            set -x
                            export RHDH_DEPLOYMENT_REPLICAS="$r"
                            export RHDH_DB_REPLICAS="$r"
                            export RHDH_DB_STORAGE="$s"
                            export RHDH_RESOURCES_CPU_REQUESTS="$cr"
                            export RHDH_RESOURCES_CPU_LIMITS="$cl"
                            export RHDH_RESOURCES_MEMORY_REQUESTS="$mr"
                            export RHDH_RESOURCES_MEMORY_LIMITS="$ml"
                            export RHDH_KEYCLOAK_REPLICAS=$r
                            export BACKSTAGE_USER_COUNT=$bu
                            export GROUP_COUNT=$bg
                            export WORKERS=$w
                            export API_COUNT=$c
                            export COMPONENT_COUNT=$c
                            index="${r}r-db_${s}-${bu}bu-${bg}bg-${w}w-${cr}cr-${cl}cl-${mr}mr-${ml}ml-${c}c"
                            set +x
                            oc login "$OPENSHIFT_API" -u "$OPENSHIFT_USERNAME" -p "$OPENSHIFT_PASSWORD" --insecure-skip-tls-verify=true
                            make undeploy-rhdh
                            setup_artifacts="$SCALABILITY_ARTIFACTS/$index/setup"
                            mkdir -p "$setup_artifacts"
                            ARTIFACT_DIR=$setup_artifacts ./ci-scripts/setup.sh |& tee "$setup_artifacts/setup.log"
                            wait_for_indexing |& tee "$setup_artifacts/after-setup-search.log"
                            for au_sr in "${active_users_spawn_rate[@]}"; do
                                IFS=":" read -ra tokens <<<"${au_sr}"
                                active_users=${tokens[0]}
                                spawn_rate=${tokens[1]}
                                echo
                                echo "/// Running the scalability test ///"
                                echo
                                set -x
                                export SCENARIO=${SCENARIO:-search-catalog}
                                export USERS="${active_users}"
                                export DURATION=${DURATION:-5m}
                                export SPAWN_RATE="${spawn_rate}"
                                set +x
                                make clean
                                test_artifacts="$SCALABILITY_ARTIFACTS/$index/test/${active_users}u"
                                mkdir -p "$test_artifacts"
                                wait_for_indexing |& tee "$test_artifacts/before-test-search.log"
                                ARTIFACT_DIR=$test_artifacts ./ci-scripts/test.sh |& tee "$test_artifacts/test.log"
                                ARTIFACT_DIR=$test_artifacts ./ci-scripts/collect-results.sh |& tee "$test_artifacts/collect-results.log"
                            done
                        done
                    done
                done
            done
        done
    done
done
popd || exit
