#!/bin/bash

set -eu

function configure_run() {
    if ! [ -f test.env ]; then
        echo "$(date -Ins --utc) FATAL Can not reach 'test.env' file. Are you in backstage-performance directory?"
        exit 1
    fi
    if [ -z "$GITHUB_TOKEN" ]; then
        echo "$(date -Ins --utc) FATAL Please export GITHUB_TOKEN. It is needed to create PRs."
        exit 1
    fi

    ticket="$1"
    branch="$2"
    testname="$3"

    git checkout "$SOURCE_BRANCH"
    git checkout -b "$branch"

    echo "
export DURATION=$DURATION
export PRE_LOAD_DB=true
export SCALE_ACTIVE_USERS_SPAWN_RATES='100:5'
export SCALE_BS_USERS_GROUPS='$SCALE_BS_USERS_GROUPS'
export SCALE_CATALOG_SIZES='$SCALE_CATALOG_SIZES'
export SCALE_CPU_REQUESTS_LIMITS=:
export SCALE_DB_STORAGES='$SCALE_DB_STORAGES'
export SCALE_MEMORY_REQUESTS_LIMITS=:
export SCALE_REPLICAS=1
export SCALE_WORKERS=20
export ENABLE_RBAC=true
export SCENARIO=mvp
export USE_PR_BRANCH=true
export WAIT_FOR_SEARCH_INDEX=false
export RHDH_HELM_CHART=redhat-developer-hub
export AUTH_PROVIDER=keycloak
export RHDH_HELM_REPO='$RHDH_HELM_REPO'
" >>test.env

    git commit -am "chore($ticket): $testname on $branch"
    git push -u origin "$branch"
    echo "$(date -Ins --utc) INFO Created and pushed branch ${branch}"
    git checkout "$SOURCE_BRANCH"

    curl_data='{
        "title": "chore('"$ticket"'): '"$branch"'",
        "body": "**'"$testname"'**: '"$VERSION_OLD"' vs. '"$VERSION_NEW"' testing. This is to get perf&scale data for `'"$branch"'`",
        "head": "'"$branch"'",
        "base": "'"$SOURCE_BRANCH"'",
        "draft": true
    }'
    curl_out="$( curl \
        -L \
        --silent \
        -X POST \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/repos/redhat-performance/backstage-performance/pulls" \
        -d "$curl_data"
    )"
    pr_number=$( echo "$curl_out" | jq -rc '.number' )
    curl_comment_out="$( curl \
        -L \
        --silent \
        -X POST \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/repos/redhat-performance/backstage-performance/issues/$pr_number/comments" \
        -d '{"body":"/test mvp-scalability"}'
    )"
    comment_url=$( echo "$curl_comment_out" | jq -rc '.html_url' )
    echo "$(date -Ins --utc) INFO Triggered build by ${comment_url}"
}

function _test() {
    name="$1"
    nick="$2"
    ticket="$3"

    branch_old="test-$VERSION_NEW-$nick-$VERSION_OLD"
    export RHDH_HELM_REPO="$RHDH_HELM_REPO_OLD"
    export SOURCE_BRANCH="$SOURCE_BRANCH_OLD"
    configure_run "$ticket" "$branch_old" "$name"

    branch_new="test-$VERSION_NEW-$nick-$VERSION_NEW"
    export RHDH_HELM_REPO="$RHDH_HELM_REPO_NEW"
    export SOURCE_BRANCH="$SOURCE_BRANCH_NEW"
    configure_run "$ticket" "$branch_new" "$name"
}

function compare_previous_test() {
    name="Compare to previous release"
    nick="compare"
    ticket="$1"   # Jira task for comparison tests

    export DURATION="15m"
    export SCALE_BS_USERS_GROUPS="1000:250 1000:250 1000:250 1000:250 1000:250"
    export SCALE_CATALOG_SIZES="2500:2500"
    export SCALE_DB_STORAGES="1Gi"

    _test "$name" "$nick" "$ticket"
}

function entity_burden_test() {
    name="Entity burden test"
    nick="entity"
    ticket="$1"   # Jira task for entity burden tests

    export DURATION="15m"
    export SCALE_BS_USERS_GROUPS="100:20"
    export SCALE_CATALOG_SIZES="1:1 5000:5000 10000:10000 15000:15000 20000:20000 25000:25000 30000:30000"
    export SCALE_DB_STORAGES="20Gi"

    _test "$name" "$nick" "$ticket"
}

function storage_limit_test() {
    name="Storage limit test"
    nick="storage"
    ticket="$1"   # Jira task for storage tests

    export DURATION="15m"
    export SCALE_BS_USERS_GROUPS="100:20"
    export SCALE_CATALOG_SIZES="1:1 3000:3000 4000:4000 5000:5000 6000:6000 7000:7000 8000:8000 9000:9000 10000:10000"
    export SCALE_DB_STORAGES="1Gi"

    _test "$name" "$nick" "$ticket"
}

# !!! Configure here !!!
VERSION_OLD="1.5"
VERSION_NEW="1.6"
RHDH_HELM_REPO_OLD="https://raw.githubusercontent.com/rhdh-bot/openshift-helm-charts/refs/heads/redhat-developer-hub-1.5-178-CI/installation"
RHDH_HELM_REPO_NEW="https://raw.githubusercontent.com/rhdh-bot/openshift-helm-charts/refs/heads/redhat-developer-hub-1.6-72-CI/installation"
SOURCE_BRANCH_OLD=rhdh-v1.5.x
SOURCE_BRANCH_NEW=main
compare_previous_test "RHIDP-6832"
entity_burden_test "RHIDP-6841"
storage_limit_test "RHIDP-6834"
