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
export ENSURE_CATALOG_POPULATION_TIMEOUT=7200
export CATALOG_REFRESH_INTERVAL_MINUTES=720
export RHDH_STARTUP_TIMEOUT_SECONDS=7200
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
    export SCALE_MEMORY_REQUESTS_LIMITS=":"
    export SCALE_COMBINED="10:2:1000:10000:2500:2500 50:5:5000:50000:12500:12500 100:10:10000:150000:25000:25000"

    _test "$name" "$nick" "$ticket"
}

function rbac_nested_test() {
    name="RBAC Nested test"
    nick="rbac_nested"
    ticket="$1" # Jira story

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
    export SCALE_MEMORY_REQUESTS_LIMITS=":"
    export SCALE_COMBINED="10:2:1000:10000:2500:2500 50:5:5000:50000:12500:12500 100:10:10000:150000:25000:25000"

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
VERSION_OLD="1.8"
VERSION_NEW="1.9"
RHDH_HELM_CHART_VERSION_OLD=1.8.2
RHDH_HELM_CHART_VERSION_NEW=1.9-200-CI
SOURCE_BRANCH_OLD=rhdh-v1.8.x
SOURCE_BRANCH_NEW=main

run_mvp_compare() {
    mvp_compare_test "RHIDP-XXXX" "$@"
}
run_mvp_memory_scale() {
    mvp_memory_scale_test "RHIDP-XXXX" "$@"
}
run_mvp_replicas_scale() {
    mvp_replicas_scale_test "RHIDP-XXXX" "$@"
}

run_orchestrator_compare() {
    orchestrator_compare_test "RHIDP-XXXX" "$@"
}
run_orchestrator_memory_scale() {
    orchestrator_memory_scale_test "RHIDP-XXXX" "$@"
}
run_orchestrator_replicas_scale() {
    orchestrator_replicas_scale_test "RHIDP-XXXX" "$@"
}

run_rbac_groups_test() {
    rbac_groups_test "RHIDP-XXXX"
}
run_rbac_nested_test() {
    rbac_nested_test "RHIDP-XXXX"
}

# Compare test: 5 iterations, 1 replica. Optional: memory e.g. "1Gi:2Gi"
run_complex_rbac_compare() {
    complex_rbac_compare_test "RHIDP-XXXX" "$@"
}

# Memory one: compare test with optional memory (memory-scale).
run_complex_rbac_memory_scale() {
    complex_rbac_memory_scale_test "RHIDP-XXXX" "$@"
}

# Replicas scale test: lower 3 scales, replicas 1..5. Optional: memory.
run_complex_rbac_replicas_scale() {
    complex_rbac_replicas_scale_test "RHIDP-XXXX" "$@"
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
        run_rbac_groups_test
        ;;
    "rbac_nested")
        run_rbac_nested_test
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
        # run_orchestrator_compare
        # run_orchestrator_memory_scale
        # run_orchestrator_replicas_scale
        # run_rbac_groups_test
        # run_rbac_nested_test
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
