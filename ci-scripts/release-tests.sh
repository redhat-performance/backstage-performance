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
export RBAC_POLICY='${RBAC_POLICY:-all_groups_admin_inherited}'
export ENABLE_RBAC=${ENABLE_RBAC:-true}
export SCENARIO=${SCENARIO:-mvp}
export USE_PR_BRANCH=${USE_PR_BRANCH:-true}
export WAIT_FOR_SEARCH_INDEX=${WAIT_FOR_SEARCH_INDEX:-false}
export RHDH_HELM_CHART=${RHDH_HELM_CHART:-redhat-developer-hub}
export AUTH_PROVIDER=${AUTH_PROVIDER:-keycloak}
export ENABLE_ORCHESTRATOR=${ENABLE_ORCHESTRATOR:-true}
export RHDH_HELM_CHART_VERSION=${RHDH_HELM_CHART_VERSION:-}
export ALWAYS_CLEANUP=${ALWAYS_CLEANUP:-false}
export SCALE_COMBINED='${SCALE_COMBINED:-}'
export LOCUST_EXTRA_CMD=${LOCUST_EXTRA_CMD:---reset-stats}
export PAGE_N_COUNT=${PAGE_N_COUNT:-0}
export CATALOG_TAB_N_COUNT=${CATALOG_TAB_N_COUNT:-0}
export ENSURE_CATALOG_POPULATION_TIMEOUT=${ENSURE_CATALOG_POPULATION_TIMEOUT:-7200}
export CATALOG_REFRESH_INTERVAL_MINUTES=${CATALOG_REFRESH_INTERVAL_MINUTES:-10080}
export RHDH_STARTUP_TIMEOUT_SECONDS=${RHDH_STARTUP_TIMEOUT_SECONDS:-7200}
export RHDH_NODEJS_MAX_HEAP_SIZE=${RHDH_NODEJS_MAX_HEAP_SIZE:-2048}
" >test.env
    git commit -am "chore($ticket): $testname on $branch"
    git push -fu origin "$branch"
    echo "$(date -u +'%Y-%m-%dT%H:%M:%S,%N+00:00') INFO Pushed branch ${branch}"
    git checkout "$SOURCE_BRANCH"

    sleep 5s
    pulls_out="$(
        curl -L --silent \
            -H "Accept: application/vnd.github+json" \
            -H "Authorization: Bearer $GITHUB_TOKEN" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            "https://api.github.com/repos/redhat-performance/backstage-performance/pulls?head=redhat-performance:$branch&state=open"
    )"
    # List endpoint returns an array; auth/errors return an object — avoid jq indexing objects as arrays.
    pr_number=$(echo "$pulls_out" | jq -rc 'if type == "array" then (.[0].number // empty) else empty end')
    if [ -z "$pr_number" ] && ! echo "$pulls_out" | jq -e 'type == "array"' >/dev/null 2>&1; then
        echo "$(date -u +'%Y-%m-%dT%H:%M:%S,%N+00:00') FATAL GitHub API (list PRs) failed: $pulls_out" >&2
        exit 1
    fi

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
        pr_number=$(echo "$curl_out" | jq -rc '.number // empty')
        if [ -z "$pr_number" ]; then
            echo "$(date -u +'%Y-%m-%dT%H:%M:%S,%N+00:00') FATAL GitHub API (create PR) failed: $curl_out" >&2
            exit 1
        fi
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
    comment_url=$(echo "$curl_comment_out" | jq -rc '.html_url // empty')
    if [ -z "$comment_url" ]; then
        echo "$(date -u +'%Y-%m-%dT%H:%M:%S,%N+00:00') FATAL GitHub API (issue comment) failed: $curl_comment_out" >&2
        exit 1
    fi
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

function mvp_compare_test() {
    name="MVP compare test"
    nick="mvp-compare"
    ticket="$1"
    memory_limits="${2:-}"

    export DURATION="10m"
    export RHDH_LOG_LEVEL=debug
    export SCALE_WORKERS=100
    export RBAC_POLICY=all_groups_admin_inherited
    export ENABLE_ORCHESTRATOR=false
    export SCENARIO=mvp
    export ALWAYS_CLEANUP=true

    export SCALE_RBAC_POLICY_SIZE="1000"
    export SCALE_REPLICAS="1:1"
    export SCALE_DB_STORAGES="20Gi"
    export SCALE_CPU_REQUESTS_LIMITS=":"
    export SCALE_MEMORY_REQUESTS_LIMITS="${memory_limits:-:}"
    export SCALE_COMBINED="10:2:1000:10000:2500:2500 10:2:1000:10000:2500:2500 10:2:1000:10000:2500:2500 10:2:1000:10000:2500:2500 10:2:1000:10000:2500:2500"

    _test "$name" "$nick" "$ticket"
}

function mvp_memory_scale_test() {
    name="MVP memory scale"
    nick="mvp-memory-scale"
    ticket="$1"
    memory_limits="${2:-}"

    export DURATION="10m"
    export RHDH_LOG_LEVEL=debug
    export SCALE_WORKERS=100
    export RBAC_POLICY=all_groups_admin_inherited
    export ENABLE_ORCHESTRATOR=false
    export SCENARIO=mvp
    export ALWAYS_CLEANUP=true

    export SCALE_RBAC_POLICY_SIZE="1000"
    export SCALE_REPLICAS="1:1"
    export SCALE_DB_STORAGES="20Gi"
    export SCALE_CPU_REQUESTS_LIMITS=":"
    export SCALE_MEMORY_REQUESTS_LIMITS="${memory_limits:-:}"
    export SCALE_COMBINED="10:2:1000:10000:2500:2500 50:5:5000:50000:12500:12500 100:10:10000:150000:25000:25000"

    _test "$name" "$nick" "$ticket"
}

function mvp_replicas_scale_test() {
    name="MVP replicas scale test"
    nick="mvp-replicas-scale"
    ticket="$1"
    memory_limits="${2:-}"

    export DURATION="10m"
    export RHDH_LOG_LEVEL=debug
    export SCALE_WORKERS=100
    export RBAC_POLICY=all_groups_admin_inherited
    export ENABLE_ORCHESTRATOR=false
    export SCENARIO=mvp
    export ALWAYS_CLEANUP=true

    export SCALE_RBAC_POLICY_SIZE="1000"
    export SCALE_REPLICAS="1:1 3:3 5:5"
    export SCALE_DB_STORAGES="20Gi"
    export SCALE_CPU_REQUESTS_LIMITS=":"
    export SCALE_MEMORY_REQUESTS_LIMITS="${memory_limits:-:}"
    export SCALE_COMBINED="10:2:1000:10000:2500:2500 50:5:5000:50000:12500:12500 100:10:10000:150000:25000:25000"

    _test "$name" "$nick" "$ticket"
}

function entity_burden_compare_test() {
    name="Entity burden test"
    nick="entity-burden-compare"
    ticket="$1" # Jira story
    memory_limits="${2:-}"

    export DURATION="15m"
    export SCALE_BS_USERS_GROUPS="100:20"
    export SCALE_CATALOG_SIZES="1:1 5000:5000 10000:10000 15000:15000 20000:20000 25000:25000 30000:30000"
    export SCALE_DB_STORAGES="20Gi"
    export SCALE_MEMORY_REQUESTS_LIMITS="${memory_limits:-:}"

    _test "$name" "$nick" "$ticket"
}

function storage_limit_compare_test() {
    name="Storage limit test"
    nick="storage-limit-compare"
    ticket="$1" # Jira story
    memory_limits="${2:-}"

    export DURATION="15m"
    export SCALE_BS_USERS_GROUPS="100:20"
    export SCALE_CATALOG_SIZES="1:1 3000:3000 4000:4000 5000:5000 6000:6000 7000:7000 8000:8000 9000:9000 10000:10000"
    export SCALE_DB_STORAGES="1Gi"
    export SCALE_MEMORY_REQUESTS_LIMITS="${memory_limits:-:}"
    
    export ENSURE_CATALOG_POPULATION_TIMEOUT=14400
    export CATALOG_REFRESH_INTERVAL_MINUTES=10080
    export RHDH_STARTUP_TIMEOUT_SECONDS=14400

    _test "$name" "$nick" "$ticket"
}

function orchestrator_compare_test() {
    name="Orchestrator compare test"
    nick="orchestrator-compare"
    ticket="$1"
    memory_limits="${2:-}"

    export DURATION="10m"
    export RHDH_LOG_LEVEL=debug
    export SCALE_WORKERS=100
    export RBAC_POLICY=all_groups_admin_inherited
    export ENABLE_ORCHESTRATOR=true
    export SCENARIO=orchestrator
    export ALWAYS_CLEANUP=true

    export SCALE_RBAC_POLICY_SIZE="1000"
    export SCALE_REPLICAS="1:1"
    export SCALE_DB_STORAGES="20Gi"
    export SCALE_CPU_REQUESTS_LIMITS=":"
    export SCALE_MEMORY_REQUESTS_LIMITS="${memory_limits:-:}"
    export SCALE_COMBINED="10:2:1000:10000:2500:2500 10:2:1000:10000:2500:2500 10:2:1000:10000:2500:2500 10:2:1000:10000:2500:2500 10:2:1000:10000:2500:2500"

    _test "$name" "$nick" "$ticket"
}

function orchestrator_memory_scale_test() {
    name="Orchestrator memory scale"
    nick="orchestrator-memory-scale"
    ticket="$1"
    memory_limits="${2:-}"

    export DURATION="10m"
    export RHDH_LOG_LEVEL=debug
    export SCALE_WORKERS=100
    export RBAC_POLICY=all_groups_admin_inherited
    export ENABLE_ORCHESTRATOR=true
    export SCENARIO=orchestrator
    export ALWAYS_CLEANUP=true

    export SCALE_RBAC_POLICY_SIZE="1000"
    export SCALE_REPLICAS="1:1"
    export SCALE_DB_STORAGES="20Gi"
    export SCALE_CPU_REQUESTS_LIMITS=":"
    export SCALE_MEMORY_REQUESTS_LIMITS="${memory_limits:-:}"
    export SCALE_COMBINED="10:2:1000:10000:2500:2500 50:5:5000:50000:12500:12500 100:10:10000:150000:25000:25000"

    _test "$name" "$nick" "$ticket"
}

function orchestrator_replicas_scale_test() {
    name="Orchestrator replicas scale test"
    nick="orchestrator-replicas-scale"
    ticket="$1"
    memory_limits="${2:-}"

    export DURATION="10m"
    export RHDH_LOG_LEVEL=debug
    export SCALE_WORKERS=100
    export RBAC_POLICY=all_groups_admin_inherited
    export ENABLE_ORCHESTRATOR=true
    export SCENARIO=orchestrator
    export ALWAYS_CLEANUP=true

    export SCALE_RBAC_POLICY_SIZE="1000"
    export SCALE_REPLICAS="1:1 3:3 5:5"
    export SCALE_DB_STORAGES="20Gi"
    export SCALE_CPU_REQUESTS_LIMITS=":"
    export SCALE_MEMORY_REQUESTS_LIMITS="${memory_limits:-:}"
    export SCALE_COMBINED="10:2:1000:10000:2500:2500 50:5:5000:50000:12500:12500 100:10:10000:150000:25000:25000"

    _test "$name" "$nick" "$ticket"
}

function rbac_groups_test() {
    name="RBAC Groups test"
    nick="rbac_groups"
    ticket="$1" # Jira story
    memory_limits="${2:-}"

    export DURATION="10m"
    export RHDH_LOG_LEVEL=debug
    export SCALE_WORKERS=100
    export RBAC_POLICY=user_in_multiple_groups
    export ENABLE_ORCHESTRATOR=false
    export SCENARIO=mvp
    export ALWAYS_CLEANUP=true

    export SCALE_RBAC_POLICY_SIZE="10000"
    export SCALE_REPLICAS="1:1"
    export SCALE_DB_STORAGES="20Gi"
    export SCALE_CPU_REQUESTS_LIMITS=":"
    export SCALE_MEMORY_REQUESTS_LIMITS="${memory_limits:-:}"
    export SCALE_COMBINED="10:2:1000:10000:2500:2500 50:5:5000:50000:12500:12500 100:10:10000:150000:25000:25000"

    _test "$name" "$nick" "$ticket"
}

function rbac_nested_test() {
    name="RBAC Nested test"
    nick="rbac_nested"
    ticket="$1" # Jira story
    memory_limits="${2:-}"

    export DURATION="10m"
    export RHDH_LOG_LEVEL=debug
    export SCALE_WORKERS=100
    export RBAC_POLICY=nested_groups
    export ENABLE_ORCHESTRATOR=false
    export SCENARIO=mvp
    export ALWAYS_CLEANUP=true

    export SCALE_RBAC_POLICY_SIZE="1000"
    export SCALE_REPLICAS="1:1"
    export SCALE_DB_STORAGES="20Gi"
    export SCALE_CPU_REQUESTS_LIMITS=":"
    export SCALE_MEMORY_REQUESTS_LIMITS="${memory_limits:-:}"
    export SCALE_COMBINED="10:2:1000:10000:2500:2500 50:5:5000:50000:12500:12500 100:10:10000:150000:25000:25000"

    _test "$name" "$nick" "$ticket"
}

function ui_baseline_compare_test() {
    name="UI baseline compare test"
    nick="ui-baseline-compare"
    ticket="$1"
    memory_limits="${2:-}"

    export DURATION="10m"
    export RHDH_LOG_LEVEL=debug
    export SCALE_WORKERS=1
    export RBAC_POLICY=all_groups_admin_inherited
    export ENABLE_ORCHESTRATOR=true
    export SCENARIO=ui-baseline
    export ALWAYS_CLEANUP=true

    export SCALE_RBAC_POLICY_SIZE="1000"
    export SCALE_REPLICAS="1:1"
    export SCALE_DB_STORAGES="20Gi"
    export SCALE_CPU_REQUESTS_LIMITS=":"
    export SCALE_MEMORY_REQUESTS_LIMITS="${memory_limits:-:}"
    export SCALE_COMBINED="1:1:1000:10000:2500:2500 1:1:1000:10000:2500:2500 1:1:1000:10000:2500:2500 1:1:1000:10000:2500:2500 1:1:1000:10000:2500:2500"

    export PAGE_N_COUNT=0
    export CATALOG_TAB_N_COUNT=0

    _test "$name" "$nick" "$ticket"
}

function ui_dynamic_plugins_compare_test() {
    name="UI dynamic plugins compare test"
    nick="ui-dynamic-plugins-compare"
    ticket="$1"
    memory_limits="${2:-}"

    export DURATION="10m"
    export RHDH_LOG_LEVEL=debug
    export SCALE_WORKERS=1
    export RBAC_POLICY=all_groups_admin_inherited
    export ENABLE_ORCHESTRATOR=true
    export SCENARIO=ui-baseline
    export ALWAYS_CLEANUP=true

    export SCALE_RBAC_POLICY_SIZE="1000"
    export SCALE_REPLICAS="1:1"
    export SCALE_DB_STORAGES="20Gi"
    export SCALE_CPU_REQUESTS_LIMITS=":"
    export SCALE_MEMORY_REQUESTS_LIMITS="${memory_limits:-:}"
    export SCALE_COMBINED="1:1:1000:10000:2500:2500 1:1:1000:10000:2500:2500 1:1:1000:10000:2500:2500 1:1:1000:10000:2500:2500 1:1:1000:10000:2500:2500"

    export PAGE_N_COUNT=100
    export CATALOG_TAB_N_COUNT=100

    _test "$name" "$nick" "$ticket"
}

function large_scale_xs_compare_test() {
    name="Large scale XS compare test"
    nick="large-scale-xs-compare"
    ticket="$1"

    export DURATION="10m"
    export RHDH_LOG_LEVEL=debug
    export SCALE_WORKERS=10
    export RBAC_POLICY=all_groups_admin_inherited
    export ENABLE_ORCHESTRATOR=true
    export SCENARIO=mvp
    export ALWAYS_CLEANUP=true

    export SCALE_RBAC_POLICY_SIZE="10000"
    export SCALE_REPLICAS="3:1"
    export SCALE_DB_STORAGES="20Gi"
    export SCALE_CPU_REQUESTS_LIMITS="3:3"
    export SCALE_MEMORY_REQUESTS_LIMITS="2Gi:2Gi"
    export RHDH_NODEJS_MAX_HEAP_SIZE=2048
    export SCALE_COMBINED="10:1:1000:10000:1250:1250" # Format "activeusers:spawnrate:users:groups:apis:components"

    export PAGE_N_COUNT=0
    export CATALOG_TAB_N_COUNT=0

    export ENSURE_CATALOG_POPULATION_TIMEOUT=18000
    export CATALOG_REFRESH_INTERVAL_MINUTES=10080
    export RHDH_STARTUP_TIMEOUT_SECONDS=18000

    _test "$name" "$nick" "$ticket"
}

function large_scale_s_compare_test() {
    name="Large scale S compare test"
    nick="large-scale-s-compare"
    ticket="$1"

    export DURATION="10m"
    export RHDH_LOG_LEVEL=debug
    export SCALE_WORKERS=50
    export RBAC_POLICY=all_groups_admin_inherited
    export ENABLE_ORCHESTRATOR=true
    export SCENARIO=mvp
    export ALWAYS_CLEANUP=true

    export SCALE_RBAC_POLICY_SIZE="50000"
    export SCALE_REPLICAS="3:1"
    export SCALE_DB_STORAGES="20Gi"
    export SCALE_CPU_REQUESTS_LIMITS="3:3"
    export SCALE_MEMORY_REQUESTS_LIMITS="2Gi:2Gi"
    export RHDH_NODEJS_MAX_HEAP_SIZE=2048
    export SCALE_COMBINED="50:5:5000:50000:7500:7500" # Format "activeusers:spawnrate:users:groups:apis:components"

    export PAGE_N_COUNT=0
    export CATALOG_TAB_N_COUNT=0

    export ENSURE_CATALOG_POPULATION_TIMEOUT=18000
    export CATALOG_REFRESH_INTERVAL_MINUTES=10080
    export RHDH_STARTUP_TIMEOUT_SECONDS=18000

    _test "$name" "$nick" "$ticket"
}

function large_scale_m_compare_test() {
    name="Large scale M compare test"
    nick="large-scale-m-compare"
    ticket="$1"

    export DURATION="10m"
    export RHDH_LOG_LEVEL=debug
    export SCALE_WORKERS=50
    export RBAC_POLICY=all_groups_admin_inherited
    export ENABLE_ORCHESTRATOR=true
    export SCENARIO=mvp
    export ALWAYS_CLEANUP=true

    export SCALE_RBAC_POLICY_SIZE="50000"
    export SCALE_REPLICAS="3:1"
    export SCALE_DB_STORAGES="20Gi"
    export SCALE_CPU_REQUESTS_LIMITS="3:3"
    export SCALE_MEMORY_REQUESTS_LIMITS="2Gi:2Gi"
    export RHDH_NODEJS_MAX_HEAP_SIZE=2048
    export SCALE_COMBINED="100:10:10000:150000:12500:12500" # Format "activeusers:spawnrate:users:groups:apis:components"

    export PAGE_N_COUNT=0
    export CATALOG_TAB_N_COUNT=0

    export ENSURE_CATALOG_POPULATION_TIMEOUT=18000
    export CATALOG_REFRESH_INTERVAL_MINUTES=10080
    export RHDH_STARTUP_TIMEOUT_SECONDS=18000

    _test "$name" "$nick" "$ticket"
}

function large_scale_l_compare_test() {
    name="Large scale L compare test"
    nick="large-scale-l-compare"
    ticket="$1"

    export DURATION="10m"
    export RHDH_LOG_LEVEL=debug
    export SCALE_WORKERS=50
    export RBAC_POLICY=all_groups_admin_inherited
    export ENABLE_ORCHESTRATOR=true
    export SCENARIO=mvp
    export ALWAYS_CLEANUP=true

    export SCALE_RBAC_POLICY_SIZE="50000"
    export SCALE_REPLICAS="3:1"
    export SCALE_DB_STORAGES="50Gi"
    export SCALE_CPU_REQUESTS_LIMITS="3:3"
    export SCALE_MEMORY_REQUESTS_LIMITS="6Gi:6Gi"
    export RHDH_NODEJS_MAX_HEAP_SIZE=4096
    export SCALE_COMBINED="200:20:20000:350000:25000:25000" # Format "activeusers:spawnrate:users:groups:apis:components"

    export PAGE_N_COUNT=0
    export CATALOG_TAB_N_COUNT=0

    export ENSURE_CATALOG_POPULATION_TIMEOUT=18000
    export CATALOG_REFRESH_INTERVAL_MINUTES=10080
    export RHDH_STARTUP_TIMEOUT_SECONDS=18000

    _test "$name" "$nick" "$ticket"
}

function large_scale_xl_compare_test() {
    name="Large scale XL compare test"
    nick="large-scale-xl-compare"
    ticket="$1"

    export DURATION="10m"
    export RHDH_LOG_LEVEL=debug
    export SCALE_WORKERS=50
    export RBAC_POLICY=all_groups_admin_inherited
    export ENABLE_ORCHESTRATOR=true
    export SCENARIO=mvp
    export ALWAYS_CLEANUP=true

    export SCALE_RBAC_POLICY_SIZE="50000"
    export SCALE_REPLICAS="3:1"
    export SCALE_DB_STORAGES="100Gi"
    export SCALE_CPU_REQUESTS_LIMITS="3:3"
    export SCALE_MEMORY_REQUESTS_LIMITS="32Gi:31Gi"
    export RHDH_NODEJS_MAX_HEAP_SIZE=30720
    export SCALE_COMBINED="300:30:30000:500000:35000:35000" # Format "activeusers:spawnrate:users:groups:apis:components"

    export PAGE_N_COUNT=0
    export CATALOG_TAB_N_COUNT=0

    export ENSURE_CATALOG_POPULATION_TIMEOUT=18000
    export CATALOG_REFRESH_INTERVAL_MINUTES=10080
    export RHDH_STARTUP_TIMEOUT_SECONDS=18000

    _test "$name" "$nick" "$ticket"
}

function complex_rbac_compare_test() {
    name="Complex RBAC compare test"
    nick="complex-rbac-compare"
    ticket="$1"
    memory_limits="${2:-}"

    export DURATION="10m"
    export RHDH_LOG_LEVEL=debug
    export SCALE_WORKERS=100
    export RBAC_POLICY=complex
    export ENABLE_ORCHESTRATOR=true
    export SCENARIO=complex-rbac
    export ALWAYS_CLEANUP=true

    export SCALE_REPLICAS="1:1"
    export SCALE_DB_STORAGES="20Gi"
    export SCALE_CPU_REQUESTS_LIMITS=":"
    export SCALE_MEMORY_REQUESTS_LIMITS="${memory_limits:-:}"
    export SCALE_COMBINED="10:2:1000:10000:2500:2500 10:2:1000:10000:2500:2500 10:2:1000:10000:2500:2500 10:2:1000:10000:2500:2500 10:2:1000:10000:2500:2500"

    _test "$name" "$nick" "$ticket"
}

function complex_rbac_memory_scale_test() {
    name="Complex RBAC memory scale"
    nick="complex-rbac-memory-scale"
    ticket="$1"
    memory_limits="${2:-}"

    export DURATION="10m"
    export RHDH_LOG_LEVEL=debug
    export SCALE_WORKERS=100
    export RBAC_POLICY=complex
    export ENABLE_ORCHESTRATOR=true
    export SCENARIO=complex-rbac
    export ALWAYS_CLEANUP=true

    export SCALE_REPLICAS="1:1"
    export SCALE_DB_STORAGES="20Gi"
    export SCALE_CPU_REQUESTS_LIMITS=":"
    export SCALE_MEMORY_REQUESTS_LIMITS="${memory_limits:-:}"
    export SCALE_COMBINED="10:2:1000:10000:2500:2500 50:5:5000:50000:12500:12500 100:10:10000:150000:25000:25000"

    _test "$name" "$nick" "$ticket"
}

function complex_rbac_replicas_scale_test() {
    name="Complex RBAC replicas scale test"
    nick="complex-rbac-replicas-scale"
    ticket="$1"
    memory_limits="${2:-}"

    export DURATION="10m"
    export RHDH_LOG_LEVEL=debug
    export SCALE_WORKERS=100
    export RBAC_POLICY=complex
    export ENABLE_ORCHESTRATOR=true
    export SCENARIO=complex-rbac
    export ALWAYS_CLEANUP=true

    export SCALE_REPLICAS="1:1 3:3 5:5"
    export SCALE_DB_STORAGES="20Gi"
    export SCALE_CPU_REQUESTS_LIMITS=":"
    export SCALE_MEMORY_REQUESTS_LIMITS="${memory_limits:-:}"
    # Lower 3 scales only, hardcoded
    export SCALE_COMBINED="10:2:1000:10000:2500:2500 50:5:5000:50000:12500:12500 100:10:10000:150000:25000:25000"

    _test "$name" "$nick" "$ticket"
}

# !!! Configure here !!!
VERSION_OLD="1.9"
VERSION_NEW="1.10"
RHDH_HELM_CHART_VERSION_OLD=1.9.4
RHDH_HELM_CHART_VERSION_NEW=1.10-124-CI
SOURCE_BRANCH_OLD=rhdh-v1.9.x
SOURCE_BRANCH_NEW=main

run_mvp_compare() {
    mvp_compare_test "RHIDP-13652" "$@"
}
run_mvp_memory_scale() {
    mvp_memory_scale_test "RHIDP-XXXX" "$@"
}
run_mvp_replicas_scale() {
    mvp_replicas_scale_test "RHIDP-XXXX" "$@"
}

run_entity_burden_compare() {
    entity_burden_compare_test "RHIDP-13652" "$@"
}

run_storage_limit_compare() {
    storage_limit_compare_test "RHIDP-13652" "$@"
}

run_orchestrator_compare() {
    orchestrator_compare_test "RHIDP-13652" "$@"
}
run_orchestrator_memory_scale() {
    orchestrator_memory_scale_test "RHIDP-XXXX" "$@"
}
run_orchestrator_replicas_scale() {
    orchestrator_replicas_scale_test "RHIDP-XXXX" "$@"
}

run_rbac_groups_test() {
    rbac_groups_test "RHIDP-XXXX" "$@"
}
run_rbac_nested_test() {
    rbac_nested_test "RHIDP-XXXX" "$@"
}

# Compare test: 5 iterations, 1 replica. Optional: memory e.g. "1Gi:2Gi"
run_complex_rbac_compare() {
    complex_rbac_compare_test "RHIDP-13652" "$@"
}

# Memory one: compare test with optional memory (memory-scale).
run_complex_rbac_memory_scale() {
    complex_rbac_memory_scale_test "RHIDP-XXXX" "$@"
}

# Replicas scale test: lower 3 scales, replicas 1..5. Optional: memory.
run_complex_rbac_replicas_scale() {
    complex_rbac_replicas_scale_test "RHIDP-XXXX" "$@"
}

run_ui_baseline_compare() {
    ui_baseline_compare_test "RHIDP-13654" "$@"
}

run_ui_dynamic_plugins_compare() {
    ui_dynamic_plugins_compare_test "RHIDP-13654" "$@"
}

run_large_scale_xs_compare() {
    large_scale_xs_compare_test "RHIDP-13655"
}
run_large_scale_s_compare() {
    large_scale_s_compare_test "RHIDP-13655"
}
run_large_scale_m_compare() {
    large_scale_m_compare_test "RHIDP-13655"
}
run_large_scale_l_compare() {
    large_scale_l_compare_test "RHIDP-13655"
}
run_large_scale_xl_compare() {
    large_scale_xl_compare_test "RHIDP-13655"
}

# Optional override: set SCALE_MEMORY_LIMITS (e.g. "1Gi:2Gi" for requests:limits) to pass
# custom memory to mvp/orchestrator/complex_rbac compare, memory_scale, and replicas_scale tests.
IFS="," read -ra test_ids <<<"${1:-all}"
for test_id in "${test_ids[@]}"; do
    case $test_id in
    "mvp_compare")
        run_mvp_compare "${SCALE_MEMORY_LIMITS:-}"
        ;;
    "mvp_memory_scale")
        run_mvp_memory_scale "${SCALE_MEMORY_LIMITS:-}"
        ;;
    "mvp_replicas_scale")
        run_mvp_replicas_scale "${SCALE_MEMORY_LIMITS:-}"
        ;;
    "entity_burden_compare")
        run_entity_burden_compare "${SCALE_MEMORY_LIMITS:-}"
        ;;
    "storage_limit_compare")
        run_storage_limit_compare "${SCALE_MEMORY_LIMITS:-}"
        ;;
    "orchestrator_compare")
        run_orchestrator_compare "${SCALE_MEMORY_LIMITS:-}"
        ;;
    "orchestrator_memory_scale")
        run_orchestrator_memory_scale "${SCALE_MEMORY_LIMITS:-}"
        ;;
    "orchestrator_replicas_scale")
        run_orchestrator_replicas_scale "${SCALE_MEMORY_LIMITS:-}"
        ;;
    "rbac_groups")
        run_rbac_groups_test "${SCALE_MEMORY_LIMITS:-}"
        ;;
    "rbac_nested")
        run_rbac_nested_test "${SCALE_MEMORY_LIMITS:-}"
        ;;
    "ui_baseline_compare")
        run_ui_baseline_compare "${SCALE_MEMORY_LIMITS:-}"
        ;;
    "ui_dynamic_plugins_compare")
        run_ui_dynamic_plugins_compare "${SCALE_MEMORY_LIMITS:-}"
        ;;
    "large_scale_xs_compare")
        run_large_scale_xs_compare
        ;;
    "large_scale_s_compare")
        run_large_scale_s_compare
        ;;
    "large_scale_m_compare")
        run_large_scale_m_compare
        ;;
    "large_scale_l_compare")
        run_large_scale_l_compare
        ;;
    "large_scale_xl_compare")
        run_large_scale_xl_compare
        ;;
    "complex_rbac_compare")
        run_complex_rbac_compare "${SCALE_MEMORY_LIMITS:-}"
        ;;
    "complex_rbac_memory_scale")
        run_complex_rbac_memory_scale "${SCALE_MEMORY_LIMITS:-}"
        ;;
    "complex_rbac_replicas_scale")
        run_complex_rbac_replicas_scale "${SCALE_MEMORY_LIMITS:-}"
        ;;
    \? | "all")
        run_mvp_compare
        run_mvp_memory_scale
        run_mvp_replicas_scale
        # run_entity_burden_compare
        # run_storage_limit_compare
        # run_orchestrator_compare
        # run_orchestrator_memory_scale
        # run_orchestrator_replicas_scale
        # run_rbac_groups_test
        # run_rbac_nested_test
        # run_ui_baseline_compare
        # run_ui_dynamic_plugins_compare
        # run_large_scale_xs_compare
        # run_large_scale_s_compare
        # run_large_scale_m_compare
        # run_large_scale_l_compare
        # run_large_scale_xl_compare
        # run_complex_rbac_compare
        # run_complex_rbac_memory_scale
        # run_complex_rbac_replicas_scale
        ;;
    *)
        echo "$(date -u +'%Y-%m-%dT%H:%M:%S,%N+00:00') ERROR Unsupported test option: '$test_id'"
        exit 1
        ;;
    esac
done
