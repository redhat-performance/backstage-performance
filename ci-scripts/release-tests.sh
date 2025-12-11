#!/bin/bash

set -u

TMP_DIR=$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "${TMP_DIR:-.tmp}")
mkdir -p "${TMP_DIR}"

WS="${TMP_DIR}/backstage-performance.git"

rm -rf "$WS"
git clone git@github.com:redhat-performance/backstage-performance.git "${WS}"
cd "${WS}" || exit 1

function configure_run() {
    if ! [ -f test.env ]; then
        echo "$(date -u +'%Y-%m-%dT%H:%M:%S,%N+00:00') FATAL Can not reach 'test.env' file. Are you in backstage-performance directory?"
        exit 1
    fi
    if [ -z "$GITHUB_TOKEN" ]; then
        echo "$(date -u +'%Y-%m-%dT%H:%M:%S,%N+00:00') FATAL Please export GITHUB_TOKEN. It is needed to create PRs."
        exit 1
    fi

    ticket="$1"
    branch="$2"
    testname="$3"

    git checkout "$SOURCE_BRANCH"
    git pull origin "$SOURCE_BRANCH"

    if git show-ref --verify --quiet refs/heads/"$branch" || git show-ref --verify --quiet refs/remotes/origin/"$branch"; then
        echo "$(date -u +'%Y-%m-%dT%H:%M:%S,%N+00:00') INFO Branch $branch exists, updating it"
        git checkout "$branch" 2>/dev/null || git checkout -b "$branch" origin/"$branch"
        git pull origin "$branch"
        git rebase origin/"$SOURCE_BRANCH"
    else
        echo "$(date -u +'%Y-%m-%dT%H:%M:%S,%N+00:00') INFO Creating new branch $branch"
        git checkout -b "$branch"
    fi

    echo "
export DURATION=${DURATION:-}
export PRE_LOAD_DB=${PRE_LOAD_DB:-true}
export SCALE_ACTIVE_USERS_SPAWN_RATES='${SCALE_ACTIVE_USERS_SPAWN_RATES:-100:5}'
export SCALE_BS_USERS_GROUPS='${SCALE_BS_USERS_GROUPS:-}'
export SCALE_CATALOG_SIZES='${SCALE_CATALOG_SIZES:-}'
export SCALE_CPU_REQUESTS_LIMITS='${SCALE_CPU_REQUESTS_LIMITS:-:}'
export SCALE_DB_STORAGES='${SCALE_DB_STORAGES:-}'
export SCALE_MEMORY_REQUESTS_LIMITS='${SCALE_MEMORY_REQUESTS_LIMITS:-:}'
export SCALE_REPLICAS='${SCALE_REPLICAS:-1:1}'
export SCALE_WORKERS='${SCALE_WORKERS:-20}'
export SCALE_RBAC_POLICY_SIZE='${SCALE_RBAC_POLICY_SIZE:-1000}'
export RBAC_POLICY='${RBAC_POLICY:-all_groups_admin}'
export ENABLE_RBAC=${ENABLE_RBAC:-true}
export SCENARIO=${SCENARIO:-mvp}
export USE_PR_BRANCH=${USE_PR_BRANCH:-true}
export WAIT_FOR_SEARCH_INDEX=${WAIT_FOR_SEARCH_INDEX:-false}
export RHDH_HELM_CHART=${RHDH_HELM_CHART:-redhat-developer-hub}
export AUTH_PROVIDER=${AUTH_PROVIDER:-keycloak}
export ENABLE_ORCHESTRATOR=${ENABLE_ORCHESTRATOR:-true}
export RHDH_HELM_CHART_VERSION=${RHDH_HELM_CHART_VERSION:-}
export ALWAYS_CLEANUP=${ALWAYS_CLEANUP:-false}
" >test.env
    git commit -am "chore($ticket): $testname on $branch"
    git push -fu origin "$branch"
    echo "$(date -u +'%Y-%m-%dT%H:%M:%S,%N+00:00') INFO Pushed branch ${branch}"
    git checkout "$SOURCE_BRANCH"

    sleep 5s
    pr_number=$(
        curl -L --silent \
            -H "Accept: application/vnd.github+json" \
            -H "Authorization: Bearer $GITHUB_TOKEN" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            "https://api.github.com/repos/redhat-performance/backstage-performance/pulls?head=redhat-performance:$branch&state=open" |
            jq -rc '.[0].number // empty'
    )

    if [ -z "$pr_number" ]; then
        curl_data='{
            "title": "chore('"$ticket"'): '"$branch"'",
            "body": "**'"$testname"'**: '"$VERSION_OLD"' vs. '"$VERSION_NEW"' testing. This is to get perf&scale data for `'"$branch"'`",
            "head": "'"$branch"'",
            "base": "'"$SOURCE_BRANCH"'",
            "draft": true
        }'
        curl_out="$(
            curl \
                -L \
                --silent \
                -X POST \
                -H "Accept: application/vnd.github+json" \
                -H "Authorization: Bearer $GITHUB_TOKEN" \
                -H "X-GitHub-Api-Version: 2022-11-28" \
                "https://api.github.com/repos/redhat-performance/backstage-performance/pulls" \
                -d "$curl_data"
        )"
        pr_number=$(echo "$curl_out" | jq -rc '.number')
    fi

    curl_comment_out="$(
        curl \
            -L \
            --silent \
            -X POST \
            -H "Accept: application/vnd.github+json" \
            -H "Authorization: Bearer $GITHUB_TOKEN" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            "https://api.github.com/repos/redhat-performance/backstage-performance/issues/$pr_number/comments" \
            -d '{"body":"/test mvp-scalability"}'
    )"
    comment_url=$(echo "$curl_comment_out" | jq -rc '.html_url')
    echo "$(date -u +'%Y-%m-%dT%H:%M:%S,%N+00:00') INFO Triggered build by ${comment_url}"

    curl \
        -L \
        --silent \
        -X POST \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/repos/redhat-performance/backstage-performance/issues/$pr_number/labels" \
        -d '{"labels":["release-tests/in-progress"]}'

    echo "$(date -u +'%Y-%m-%dT%H:%M:%S,%N+00:00') INFO Added label 'release-tests/in-progress' to PR #${pr_number}"
}

function _test() {
    name="$1"
    nick="$2"
    ticket="$3"

    branch_old="test-$VERSION_NEW-$nick-$VERSION_OLD"
    export RHDH_HELM_CHART_VERSION="$RHDH_HELM_CHART_VERSION_OLD"
    export SOURCE_BRANCH="$SOURCE_BRANCH_OLD"
    configure_run "$ticket" "$branch_old" "$name"

    branch_new="test-$VERSION_NEW-$nick-$VERSION_NEW"
    export RHDH_HELM_CHART_VERSION="$RHDH_HELM_CHART_VERSION_NEW"
    export SOURCE_BRANCH="$SOURCE_BRANCH_NEW"
    configure_run "$ticket" "$branch_new" "$name"
}

function compare_previous_test() {
    name="Compare to previous release"
    nick="compare"
    ticket="$1" # Jira story

    export DURATION="15m"
    export SCALE_BS_USERS_GROUPS="1000:250 1000:250 1000:250 1000:250 1000:250"
    export SCALE_CATALOG_SIZES="2500:2500"
    export SCALE_DB_STORAGES="1Gi"

    _test "$name" "$nick" "$ticket"
}

function entity_burden_test() {
    name="Entity burden test"
    nick="entity"
    ticket="$1" # Jira story

    export DURATION="15m"
    export SCALE_BS_USERS_GROUPS="100:20"
    export SCALE_CATALOG_SIZES="1:1 5000:5000 10000:10000 15000:15000 20000:20000 25000:25000 30000:30000"
    export SCALE_DB_STORAGES="20Gi"

    _test "$name" "$nick" "$ticket"
}

function storage_limit_test() {
    name="Storage limit test"
    nick="storage"
    ticket="$1" # Jira story

    export DURATION="15m"
    export SCALE_BS_USERS_GROUPS="100:20"
    export SCALE_CATALOG_SIZES="1:1 3000:3000 4000:4000 5000:5000 6000:6000 7000:7000 8000:8000 9000:9000 10000:10000"
    export SCALE_DB_STORAGES="1Gi"

    _test "$name" "$nick" "$ticket"
}

function max_concurrency_test() {
    name="Max Concurrency test"
    nick="max_concurrency"
    ticket="$1" # Jira story

    export DURATION="10m"
    export RHDH_LOG_LEVEL=debug
    export SCALE_WORKERS=100
    export RBAC_POLICY=all_groups_admin
    export ENABLE_ORCHESTRATOR=false

    export SCALE_ACTIVE_USERS_SPAWN_RATES="1:1 10:2 25:5 50:10 100:20 150:30 200:40 250:50 300:60 350:70 400:80 500:100"
    export SCALE_BS_USERS_GROUPS="1000:250"
    export SCALE_RBAC_POLICY_SIZE="1000"
    export SCALE_CATALOG_SIZES="2500:2500"
    export SCALE_REPLICAS="1:1"
    export SCALE_DB_STORAGES="2Gi"
    export SCALE_CPU_REQUESTS_LIMITS=":"
    export SCALE_MEMORY_REQUESTS_LIMITS=":"

    _test "$name" "$nick" "$ticket"
}

function max_concurrency_ha_2_test() {
    name="Max Concurrency test HA (2 nodes)"
    nick="max_concurrency_ha_2"
    ticket="$1" # Jira story

    export DURATION="10m"
    export RHDH_LOG_LEVEL=debug
    export SCALE_WORKERS=100
    export RBAC_POLICY=all_groups_admin
    export ENABLE_ORCHESTRATOR=false

    export SCALE_ACTIVE_USERS_SPAWN_RATES="1:1 10:2 25:5 50:10 100:20 150:30 200:40 250:50 300:60 350:70 400:80 500:100"
    export SCALE_BS_USERS_GROUPS="1000:250"
    export SCALE_RBAC_POLICY_SIZE="1000"
    export SCALE_CATALOG_SIZES="2500:2500"
    export SCALE_REPLICAS="2:2"
    export SCALE_DB_STORAGES="2Gi"
    export SCALE_CPU_REQUESTS_LIMITS=":"
    export SCALE_MEMORY_REQUESTS_LIMITS=":"

    _test "$name" "$nick" "$ticket"
}

function max_concurrency_ha_3_test() {
    name="Max Concurrency test HA (3 nodes)"
    nick="max_concurrency_ha_3"
    ticket="$1" # Jira story

    export DURATION="10m"
    export RHDH_LOG_LEVEL=debug
    export SCALE_WORKERS=100
    export RBAC_POLICY=all_groups_admin
    export ENABLE_ORCHESTRATOR=false

    export SCALE_ACTIVE_USERS_SPAWN_RATES="1:1 10:2 25:5 50:10 100:20 150:30 200:40 250:50 300:60 350:70 400:80 500:100"
    export SCALE_BS_USERS_GROUPS="1000:250"
    export SCALE_RBAC_POLICY_SIZE="1000"
    export SCALE_CATALOG_SIZES="2500:2500"
    export SCALE_REPLICAS="3:3"
    export SCALE_DB_STORAGES="2Gi"
    export SCALE_CPU_REQUESTS_LIMITS=":"
    export SCALE_MEMORY_REQUESTS_LIMITS=":"

    _test "$name" "$nick" "$ticket"
}

function max_concurrency_with_orchestrator_test() {
    name="Max Concurrency with Orchestrator test"
    nick="max_concurrency_with_orchestrator"
    ticket="$1" # Jira story

    export DURATION="10m"
    export RHDH_LOG_LEVEL=debug
    export SCALE_WORKERS=100
    export RBAC_POLICY=all_groups_admin
    export ENABLE_ORCHESTRATOR=true

    export SCALE_ACTIVE_USERS_SPAWN_RATES="1:1 10:2 25:5 50:10 100:20 150:30 200:40 250:50 300:60 350:70 400:80 500:100"
    export SCALE_BS_USERS_GROUPS="1000:250"
    export SCALE_RBAC_POLICY_SIZE="1000"
    export SCALE_CATALOG_SIZES="2500:2500"
    export SCALE_REPLICAS="1:1"
    export SCALE_DB_STORAGES="2Gi"
    export SCALE_CPU_REQUESTS_LIMITS=":"
    export SCALE_MEMORY_REQUESTS_LIMITS=":"

    _test "$name" "$nick" "$ticket"
}

function orchestrator_test() {
    name="Orchestrator test"
    nick="orchestrator"
    ticket="$1" # Jira story

    export DURATION="10m"
    export RHDH_LOG_LEVEL=debug
    export SCALE_WORKERS=100
    export RBAC_POLICY=all_groups_admin
    export ENABLE_ORCHESTRATOR=true
    export SCENARIO=orchestrator
    export ALWAYS_CLEANUP=true

    export SCALE_ACTIVE_USERS_SPAWN_RATES="1:1 10:2 25:5 50:10 100:20 150:30 200:40 250:50 300:60 400:80 500:100"
    export SCALE_BS_USERS_GROUPS="1000:250"
    export SCALE_RBAC_POLICY_SIZE="1000"
    export SCALE_CATALOG_SIZES="2500:2500"
    export SCALE_REPLICAS="1:1"
    export SCALE_DB_STORAGES="2Gi"
    export SCALE_CPU_REQUESTS_LIMITS=":"
    export SCALE_MEMORY_REQUESTS_LIMITS=":"

    _test "$name" "$nick" "$ticket"
}

function orchestrator_ha_2_test() {
    name="Orchestrator test HA (2 nodes)"
    nick="orchestrator_ha_2"
    ticket="$1" # Jira story

    export DURATION="10m"
    export RHDH_LOG_LEVEL=debug
    export SCALE_WORKERS=100
    export RBAC_POLICY=all_groups_admin
    export ENABLE_ORCHESTRATOR=true
    export SCENARIO=orchestrator
    export ALWAYS_CLEANUP=true

    export SCALE_ACTIVE_USERS_SPAWN_RATES="1:1 10:2 25:5 50:10 100:20 150:30 200:40 250:50 300:60 400:80 500:100"
    export SCALE_BS_USERS_GROUPS="1000:250"
    export SCALE_RBAC_POLICY_SIZE="1000"
    export SCALE_CATALOG_SIZES="2500:2500"
    export SCALE_REPLICAS="2:2"
    export SCALE_DB_STORAGES="2Gi"
    export SCALE_CPU_REQUESTS_LIMITS=":"
    export SCALE_MEMORY_REQUESTS_LIMITS=":"

    _test "$name" "$nick" "$ticket"
}

function orchestrator_ha_3_test() {
    name="Orchestrator test HA (3 nodes)"
    nick="orchestrator_ha_3"
    ticket="$1" # Jira story

    export DURATION="10m"
    export RHDH_LOG_LEVEL=debug
    export SCALE_WORKERS=100
    export RBAC_POLICY=all_groups_admin
    export ENABLE_ORCHESTRATOR=true
    export SCENARIO=orchestrator
    export ALWAYS_CLEANUP=true

    export SCALE_ACTIVE_USERS_SPAWN_RATES="1:1 10:2 25:5 50:10 100:20 150:30 200:40 250:50 300:60 400:80 500:100"
    export SCALE_BS_USERS_GROUPS="1000:250"
    export SCALE_RBAC_POLICY_SIZE="1000"
    export SCALE_CATALOG_SIZES="2500:2500"
    export SCALE_REPLICAS="3:3"
    export SCALE_DB_STORAGES="2Gi"
    export SCALE_CPU_REQUESTS_LIMITS=":"
    export SCALE_MEMORY_REQUESTS_LIMITS=":"

    _test "$name" "$nick" "$ticket"
}   

function rbac_test() {
    name="RBAC test"
    nick="rbac"
    ticket="$1" # Jira story

    export DURATION="10m"
    export RBAC_POLICY=all_groups_admin
    export ENABLE_ORCHESTRATOR=false

    export SCALE_ACTIVE_USERS_SPAWN_RATES="1:1"
    export SCALE_BS_USERS_GROUPS="1000:250"
    export SCALE_RBAC_POLICY_SIZE="1 10 100 1000 2000 4000 8000 10000 15000 20000 25000 26000"
    export SCALE_CATALOG_SIZES="2500:2500"
    export SCALE_REPLICAS="1:1"
    export SCALE_DB_STORAGES="2Gi"
    export SCALE_CPU_REQUESTS_LIMITS=":"
    export SCALE_MEMORY_REQUESTS_LIMITS=":"

    _test "$name" "$nick" "$ticket"
}

function rbac_groups_test() {
    name="RBAC Groups test"
    nick="rbac_groups"
    ticket="$1" # Jira story

    export DURATION="10m"
    export RBAC_POLICY=user_in_multiple_groups
    export ENABLE_ORCHESTRATOR=false

    export SCALE_ACTIVE_USERS_SPAWN_RATES="1:1"
    export SCALE_BS_USERS_GROUPS="1000:1000"
    export SCALE_RBAC_POLICY_SIZE="1 10 50 100 200 300 400 500 750 1000"
    export SCALE_CATALOG_SIZES="2500:2500"
    export SCALE_REPLICAS="1:1"
    export SCALE_DB_STORAGES="2Gi"
    export SCALE_CPU_REQUESTS_LIMITS=":"
    export SCALE_MEMORY_REQUESTS_LIMITS=":"

    _test "$name" "$nick" "$ticket"
}

function rbac_nested_test() {
    name="RBAC Nested test"
    nick="rbac_nested"
    ticket="$1" # Jira story

    export DURATION="10m"
    export RBAC_POLICY=nested_groups
    export ENABLE_ORCHESTRATOR=false

    export SCALE_ACTIVE_USERS_SPAWN_RATES="1:1"
    export SCALE_BS_USERS_GROUPS="1000:1000"
    export SCALE_RBAC_POLICY_SIZE="1 10 50 100 200 300 400 500 750 1000"
    export SCALE_CATALOG_SIZES="2500:2500"
    export SCALE_REPLICAS="1:1"
    export SCALE_DB_STORAGES="2Gi"
    export SCALE_CPU_REQUESTS_LIMITS=":"
    export SCALE_MEMORY_REQUESTS_LIMITS=":"

    _test "$name" "$nick" "$ticket"
}

# !!! Configure here !!!
VERSION_OLD="1.7"
VERSION_NEW="1.8"
RHDH_HELM_CHART_VERSION_OLD=1.7.2
RHDH_HELM_CHART_VERSION_NEW=1.8-164-CI
SOURCE_BRANCH_OLD=rhdh-v1.7.x
SOURCE_BRANCH_NEW=main

run_compare_previous_test() {
    compare_previous_test "RHIDP-9162"
}
run_entity_burden_test() {
    entity_burden_test "RHIDP-9167"
}
run_storage_limit_test() {
    storage_limit_test "RHIDP-9163"
}
run_max_concurrency_test() {
    max_concurrency_test "RHIDP-9158"
}
run_max_concurrency_ha_2_test() {
    max_concurrency_ha_2_test "RHIDP-9159"
}
run_max_concurrency_ha_3_test() {
    max_concurrency_ha_3_test "RHIDP-9159"
}
run_max_concurrency_with_orchestrator_test() {
    max_concurrency_with_orchestrator_test "RHIDP-9159"
}
run_orchestrator_test() {
    orchestrator_test "RHIDP-9708"
}
run_orchestrator_ha_2_test() {
    orchestrator_ha_2_test "RHIDP-9708"
}
run_orchestrator_ha_3_test() {
    orchestrator_ha_3_test "RHIDP-9708"
}
run_rbac_test() {
    rbac_test "RHIDP-9165"
}
run_rbac_groups_test() {
    rbac_groups_test "RHIDP-9171"
}
run_rbac_nested_test() {
    rbac_nested_test "RHIDP-9173"
}

IFS="," read -ra test_ids <<<"${1:-all}"
for test_id in "${test_ids[@]}"; do
    case $test_id in
    "compare_previous")
        run_compare_previous_test
        ;;
    "entity_burden")
        run_entity_burden_test
        ;;
    "storage_limit")
        run_storage_limit_test
        ;;
    "max_concurrency")
        run_max_concurrency_test
        ;;
    "max_concurrency_ha_2")
        run_max_concurrency_ha_2_test
        ;;
    "max_concurrency_ha_3")
        run_max_concurrency_ha_3_test
        ;;
    "max_concurrency_with_orchestrator")
        run_max_concurrency_with_orchestrator_test
        ;;
    "orchestrator")
        run_orchestrator_test
        ;;
    "orchestrator_ha_2")
        run_orchestrator_ha_2_test
        ;;
    "orchestrator_ha_3")
        run_orchestrator_ha_3_test
        ;;
    "rbac")
        run_rbac_test
        ;;
    "rbac_groups")
        run_rbac_groups_test
        ;;
    "rbac_nested")
        run_rbac_nested_test
        ;;
    \? | "all")
        run_compare_previous_test
        run_entity_burden_test
        run_storage_limit_test
        # run_max_concurrency_test
        # run_max_concurrency_ha_2_test
        # run_max_concurrency_ha_3_test
        # run_max_concurrency_with_orchestrator_test
        # run_orchestrator_test
        # run_orchestrator_ha_2_test
        # run_orchestrator_ha_3_test
        # run_rbac_test
        # run_rbac_groups_test
        # run_rbac_nested_test
        ;;
    *)
        echo "$(date -u +'%Y-%m-%dT%H:%M:%S,%N+00:00') ERROR Unsupported test option: '$test_id'"
        exit 1
        ;;
    esac
done
