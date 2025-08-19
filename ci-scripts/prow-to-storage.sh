#!/bin/bash -eu

CACHE_DIR="prow-to-storage-cache-dir"
PROW_ARTIFACT_PATH="redhat-performance-backstage-performance/artifacts/benchmark.json"
ES_HOST="http://elasticsearch.intlab.perf-infra.lab.eng.rdu2.redhat.com"
HORREUM_HOST="https://horreum.corp.redhat.com"
HORREUM_TEST_NAME="rhdh-load-test"
HORREUM_TEST_SCHEMA="urn:rhdh-perf-team-load-test:1.0"
HORREUM_TEST_OWNER="rhdh-perf-test-team"
HORREUM_TEST_ACCESS="PUBLIC"

function _log() {
    echo "$(date -Ins --utc) $1 $2" >&1
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

mkdir -p "$CACHE_DIR"

if ! type jq >/dev/null; then
    fatal "Please install jq"
fi
if ! type shovel.py >/dev/null; then
    fatal "shovel.py utility not available"
fi
if [ -z "$HORREUM_API_TOKEN" ]; then
    fatal "Please provide HORREUM_API_TOKEN variable"
fi

function format_date() {
    python3 -c "from datetime import datetime, timezone;dt = datetime.strptime('$1', '%a %b %d %H:%M:%S %Z %Y');dt_utc = dt.replace(tzinfo=timezone.utc);output_format = '%Y-%m-%dT%H:%M:%SZ';print(dt_utc.strftime('%Y-%m-%dT%H:%M:%SZ'))"
}

function download() {
    local job="$1"
    local id="$2"
    local run="$3"
    local out="$4"

    if [ -f "$out" ]; then
        debug "File $out already present, skipping download"
    else
        info "Downloading $out"
        shovel.py prow --job-name "$job" download --job-run-id "$id" --run-name "$run" --artifact-path "$PROW_ARTIFACT_PATH" --output-path "$out" --record-link metadata.link
    fi
}

function check_json() {
    local f="$1"
    if jq --exit-status "." "$f" >/dev/null; then
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
    if echo "$data" | jq --exit-status "." >/dev/null; then
        return 0
    else
        error "String is not a valid JSON, bad"
        return 1
    fi
}

function check_result() {
    # Ensure benchmark.json have all the required fields => test finished
    local f="$1"
    if jq -e '.measurements.timings.benchmark.ended == null' "$f" >/dev/null; then
        error "File is missing .measurements.timings.benchmark.ended, skipping"
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
    local current_in_file
    current_in_file=$(jq --raw-output "$key" "$f")
    if [[ "$current_in_file" == "None" ]]; then
        debug "Adding $key to JSON file"
        jq "$key = \"$value\"" "$f" >"$$.json" && mv -f "$$.json" "$f"
    elif [[ "$current_in_file" != "$value" ]]; then
        debug "Changing $key in JSON file"
        jq "$key = \"$value\"" "$f" >"$$.json" && mv -f "$$.json" "$f"
    else
        debug "Key $key already in file, skipping enritchment"
    fi
}

function upload_horreum() {
    local f="$1"

    debug "Uploading file $f to Horreum"
    shovel.py horreum --base-url "$HORREUM_HOST" --api-token "$HORREUM_API_TOKEN" upload --test-name "$HORREUM_TEST_NAME" --input-file "$f" --matcher-field ".metadata.env.BUILD_ID" --matcher-label ".metadata.env.BUILD_ID" --start "@measurements.timings.benchmark.started" --end "@measurements.timings.benchmark.ended" --owner "$HORREUM_TEST_OWNER" --access "$HORREUM_TEST_ACCESS"
    shovel.py horreum --base-url "$HORREUM_HOST" --api-token "$HORREUM_API_TOKEN" result --test-name "$HORREUM_TEST_NAME" --output-file "$f" --start "@measurements.timings.benchmark.started" --end "@measurements.timings.benchmark.ended"
}

function upload_resultsdashboard() {
    local f="$1"

    debug "Uploading $f to Results Dashboard"
    shovel.py resultsdashboard --base-url $ES_HOST upload --input-file "$f" --group "Portfolio and Delivery" --product "Red Hat Developer Hub" --test @name --result-id @metadata.env.BUILD_ID --result @result --date @measurements.timings.benchmark.started --link @metadata.link --release @metadata.image.version --version @metadata.image.release
}

counter=0

# Fetch JSON files from main test that runs every 12 hours
# shellcheck disable=SC2043
for job in "mvp-cpt"; do
    prow_job="periodic-ci-redhat-performance-backstage-performance-main-$job"
    for i in $(shovel.py prow --job-name "$prow_job" list); do
        out="$CACHE_DIR/$i.benchmark.json"

        download "$prow_job" "$i" "$job" "$out"
        check_json "$out" || continue
        check_result "$out" || continue
        enritch_stuff "$out" ".\"\$schema\"" "$HORREUM_TEST_SCHEMA"
        upload_horreum "$out"
        upload_resultsdashboard "$out" || true
        ((counter++)) || true
    done
done

info "Processed $counter files"
