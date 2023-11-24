#!/bin/bash -eu

JOB_BASE="https://gcsweb-ci.apps.ci.l2s4.p1.openshiftapps.com/gcs/test-platform-results/logs/"
CACHE_DIR="prow-to-storage-cache-dir"
ES_HOST="http://elasticsearch.intlab.perf-infra.lab.eng.rdu2.redhat.com"
ES_INDEX="backstage_ci_status_data"
HORREUM_HOST="https://horreum.corp.redhat.com"
HORREUM_KEYCLOAK_HOST="https://horreum-keycloak.corp.redhat.com"
HORREUM_TEST_NAME="rhdh-load-test"
HORREUM_TEST_SCHEMA="urn:rhdh-perf-team-load-test:1.0"
HORREUM_TEST_OWNER="rhdh-perf-test-team"
HORREUM_TEST_ACCESS="PUBLIC"

mkdir -p "$CACHE_DIR"

if ! type jq >/dev/null; then
    fatal "Please install jq"
fi
if [ -z "$HORREUM_JHUTAR_PASSWORD" ]; then
    fatal "Please provide HORREUM_JHUTAR_PASSWORD variable"
fi

function _log() {
    echo "$( date -Ins --utc ) $1 $2" >&1
}

function debug() {
    _log DEBUG "$1"
}

function info() {
    _log INFO "$1"
}

function warning() {
    _log WARNING "$1"
}

function error() {
    _log ERROR "$1"
}

function fatal() {
    _log FATAL "$1"
    exit 1
}

format_date() {
    date -d "$1" +%FT%TZ --utc
}

function download() {
    local from="$1"
    local to="$2"
    if ! [ -f "$to" ]; then
        info "Downloading $from to $to"
        curl -LSsl -o "$to" "$from"
    else
        debug "File $to already present, skipping download"
    fi
}

function check_json() {
    local f="$1"
    if cat "$f" | jq --exit-status >/dev/null; then
        debug "File is valid JSON, good"
        return 0
    else
        error "File is not a valid JSON, removing it and skipping further processing"
        rm -f "$f"
        return 1
    fi
}

function check_json_string() {
    local data="$1"
    if echo "$data" | jq --exit-status >/dev/null; then
        return 0
    else
        error "String is not a valid JSON, bad"
        return 1
    fi
}

function check_result() {
    # Ensure benchmark.json have all the required fields => test finished
    local f="$1"
    if jq -e '.results.ended == null' "$f" >/dev/null; then
        error "File is missing .results.ended, skipping"
        return 1
    fi
    if jq -e '.results | length == 0' "$f" >/dev/null; then
        error "File is missing .results, skipping"
        return 1
    fi
    debug "File is finished result, good"
}

function enritch_stuff() {
    local f="$1"
    local key="$2"
    local value="$3"
    local current_in_file=$( cat "$f" | jq --raw-output "$key" )
    if [[ "$current_in_file" == "None" ]]; then
        debug "Adding $key to JSON file"
        cat $f | jq "$key = \"$value\"" >"$$.json" && mv -f "$$.json" "$f"
    elif [[ "$current_in_file" != "$value" ]]; then
        debug "Changing $key in JSON file"
        cat $f | jq "$key = \"$value\"" >"$$.json" && mv -f "$$.json" "$f"
    else
        debug "Key $key already in file, skipping enritchment"
    fi
}

function upload_es() {
    local f="$1"
    local build_id="$2"

    debug "Considering file for upload to ES"

    local current_doc_in_es="$( curl --silent -X GET $ES_HOST/$ES_INDEX/_search -H 'Content-Type: application/json' -d '{"query":{"term":{"metadata.env.BUILD_ID.keyword":{"value":"'$build_id'"}}}}' )"
    local current_count_in_es="$( echo $current_doc_in_es"" | jq --raw-output .hits.total.value )"
    local current_error_in_es="$( echo $current_doc_in_es"" | jq --raw-output .error.type )"

    if [[ "$current_error_in_es" == "index_not_found_exception" ]]; then
        info "Index does not exist yet, going on"
    else
        if [[ "$current_count_in_es" -gt 0 ]]; then
            info "Already in ES, skipping upload"
            return 0
        fi
    fi

    info "Uploading to ES"
    curl --silent \
        -X POST \
        -H 'Content-Type: application/json' \
        $ES_HOST/$ES_INDEX/_doc \
        -d "@$f" | jq --raw-output .result
}

function upload_horreum() {
    local f="$1"
    local test_name="$2"
    local test_matcher="$3"
    local build_id="$4"

    if [ ! -f "$f" -o -z "$test_name" -o -z "$test_matcher" -o -z "$build_id" ]; then
        error "Insufficient parameters when uploading to Horreum"
        return 1
    fi

    local test_start="$( format_date $( cat "$f" | jq --raw-output '.results.started | if . == "" then "-" else . end' ) )"
    local test_end="$( format_date $( cat "$f" | jq --raw-output '.results.ended | if . == "" then "-" else . end' ) )"

    if [ -z "$test_start" -o -z "$test_end" -o "$test_start" == "null" -o "$test_end" == "null" ]; then
        error "We need start ($test_start) and end ($test_end) time in the JSON we are supposed to upload"
        return 1
    fi

    debug "Considering file upload to Horreum: start: $test_start, end: $test_end, $test_matcher: $build_id"

    local TOKEN=$( curl -s $HORREUM_KEYCLOAK_HOST/realms/horreum/protocol/openid-connect/token -d "username=jhutar@redhat.com" -d "password=$HORREUM_JHUTAR_PASSWORD" -d "grant_type=password" -d "client_id=horreum-ui" | jq --raw-output .access_token )

    local test_id=$( curl --silent --get -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" "$HORREUM_HOST/api/test/byName/$test_name" | jq --raw-output .id )

    local exists=$( curl --silent --get -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" "$HORREUM_HOST/api/dataset/list/$test_id" --data-urlencode "filter={\"$test_matcher\":\"$build_id\"}" | jq --raw-output '.datasets | length' )

    if [[ $exists -gt 0 ]]; then
        info "Test result ($test_matcher=$build_id) found in Horreum ($exists), skipping upload"
        return 0
    fi

    info "Uploading file to Horreum"
    curl --silent \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $TOKEN" \
        "$HORREUM_HOST/api/run/data?test=$test_name&start=$test_start&stop=$test_end&owner=$HORREUM_TEST_OWNER&access=$HORREUM_TEST_ACCESS" \
        -d "@$f"
    echo

    info "Getting pass/fail for file from Horreum"
    local ids_list=$( curl --silent "https://horreum.corp.redhat.com/api/alerting/variables?test=$test_id" | jq -r '.[] | .id' )
    local is_fail=0
    for i in $ids_list; do
        data='{
            "range": {
                "from": "'"$test_start"'",
                "to": "'"$test_end"'",
                "oneBeforeAndAfter": true
            },
            "annotation": {
                "query": "'"$i"'"
            }
        }'

        count=$( curl --silent -H "Content-Type: application/json" "https://horreum.corp.redhat.com/api/changes/annotations" -d "$data"  | jq -r '. | length' )
        if [ "$count" -gt 0 ]; then
            is_fail=1
            enritch_stuff "$f" ".result" "FAIL"
            break
        fi
    done
    if [ $is_fail != 1 ]; then
        enritch_stuff "$f" ".result" "PASS"
    fi
}

counter=0

# Fetch JSON files from main test that runs every 12 hours
for job in "mvp-cpt"; do
    job_history="$JOB_BASE/periodic-ci-redhat-performance-backstage-performance-main-$job/"
    for i in $(curl -SsL "$job_history" | grep -Eo '[0-9]{19}' | sort -V | uniq | tail -n 5); do
        f="$job_history/$i/artifacts/$job/redhat-performance-backstage-performance/artifacts/benchmark.json"
        out="$CACHE_DIR/$i.benchmark.json"

        download "$f" "$out"
        check_json "$out" || continue
        check_result "$out" || continue
        enritch_stuff "$out" '."$schema"' "$HORREUM_TEST_SCHEMA"
        upload_horreum "$out" "$HORREUM_TEST_NAME" ".metadata.env.BUILD_ID" "$i"
        upload_es "$out" "$i"
        let counter+=1
    done
done

info "Processed $counter files"
