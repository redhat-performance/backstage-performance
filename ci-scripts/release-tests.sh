#!/bin/bash

set -eu

function configure_run() {
    if ! [ -f test.env ]; then
        echo "$(date -Ins --utc) FATAL Can not reach 'test.env' file. Are you in backstage-performance directory?"
        exit 1
    fi

    ticket="$1"
    branch="$2"
    testname="$3"

    git checkout main
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
export SCENARIO=mvp
export USE_PR_BRANCH=true
export WAIT_FOR_SEARCH_INDEX=false
export RHDH_HELM_CHART=redhat-developer-hub
export AUTH_PROVIDER=keycloak
export RHDH_HELM_REPO='$RHDH_HELM_REPO'
" >>test.env

    git commit -am "chore($ticket): $testname on $branch"
    git push -u origin "$branch"
    echo "$(date -Ins --utc) INFO Create PR on https://github.com/redhat-performance/backstage-performance/pull/new/${branch} and comment '/test mpc' there"
    git checkout main
}

function _test() {
    name="$1"
    nick="$2"
    ticket="$3"

    branch_old="test-$VERSION_NEW-$nick-$VERSION_OLD"
    export RHDH_HELM_REPO="$RHDH_HELM_REPO_OLD"
    configure_run "$ticket" "$branch_old" "$name"

    branch_new="test-$VERSION_NEW-$nick-$VERSION_NEW"
    export RHDH_HELM_REPO="$RHDH_HELM_REPO_NEW"
    configure_run "$ticket" "$branch_new" "$name"
}

function entity_burden_test() {
    name="Entity burden test"
    nick="entity"
    ticket="$1"   # Jira task for storage tests

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
    export SCALE_BS_USERS_GROUPS="10000:2000"
    export SCALE_CATALOG_SIZES="1:1 2800:2800 2900:2900 3000:3000 3100:3100 3200:3200 3300:3300 3400:3400"
    export SCALE_DB_STORAGES="1Gi"

    _test "$name" "$nick" "$ticket"
}

# !!! Configure here !!!
VERSION_OLD="1.3"
VERSION_NEW="1.4"
RHDH_HELM_REPO_OLD="https://charts.openshift.io/"
RHDH_HELM_REPO_NEW="https://raw.githubusercontent.com/rhdh-bot/openshift-helm-charts/refs/heads/redhat-developer-hub-1.4-69-CI/installation"
entity_burden_test "RHIDP-4541"
#storage_limit_test "RHIDP-4531"
