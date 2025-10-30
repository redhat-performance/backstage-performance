#!/bin/bash

# Purpose of this tool is to generate a table same as summary.csv artifact
# created by `/test mvp-scalability` for multiple runs of `/test mvp` in a PR.
#
# To use it, go to your PR, e.g.:
#
#     https://github.com/redhat-performance/backstage-performance/pull/158
#
# Open "Full PR test history" report, e.g.:
#
#     https://prow.ci.openshift.org/pr-history/?org=redhat-performance&repo=backstage-performance&pr=158
#
# and copy Prow links for runs you are interested in and pass them to this
# script on on command line:
#
#     $ ci-scripts/helper-jobs-to-csv.sh https://prow.ci.openshift.org/... https://prow.ci.openshift.org/... https://prow.ci.openshift.org/...
#
# Now the tool will generate CSV generated via `ci-scripts/runs-to-csv.sh`
# ready to be copy&pasted to spreadsheet for more processing.
#
# Example input link the script expects on the input:
#
#   https://prow.ci.openshift.org/view/gs/test-platform-results/pr-logs/pull/redhat-performance_backstage-performance/158/pull-ci-redhat-performance-backstage-performance-main-mvp/1896561250540720128

set -e -u -o pipefail

function log() {
    local text="${1}"
    echo "$( date -u -Ins ) ${text}"
}

function assert_int() {
    local input="${1}"
    if ! [[ "${input}" =~ ^[0-9]+$ ]]; then
        log "ERROR Input '${input}' is not an integer"
        return 1
    fi
}

function assert_json() {
    local input="${1}"
    if ! jq -e '.' "${input}" >/dev/null; then
        log "ERROR Input '${input}' is not JSON file"
        return 1
    fi
}

files_dir="$( mktemp -d )"
trap 'rm -rf "${files_dir}"' EXIT

for url in "$@"; do
    log "DEBUG Processing URL ${url}"
    pr_number="$( echo "${url}" | cut -d '/' -f 10 )"
    assert_int "$pr_number"
    job_id="$( echo "${url}" | cut -d '/' -f 12 )"
    assert_int "$pr_number"
    bench_url="https://gcsweb-ci.apps.ci.l2s4.p1.openshiftapps.com/gcs/test-platform-results/pr-logs/pull/redhat-performance_backstage-performance/${pr_number}/pull-ci-redhat-performance-backstage-performance-main-mvp/${job_id}/artifacts/mvp/redhat-performance-backstage-performance/artifacts/benchmark.json"
    bench_file="${files_dir}/${job_id}/benchmark.json"
    log "DEBUG Downloading URL ${bench_url} to ${bench_file}"
    mkdir -p "${files_dir}/${job_id}"
    curl -sL "$bench_url" -o "${bench_file}"
    assert_json "${bench_file}"
    log "INFO Downloaded to ${bench_file}"
done

output="$( mktemp runs-to-csv-XXXXXX.csv )"
log "INFO Storing resulting CSV as '${output}'"
ci-scripts/runs-to-csv.sh "${files_dir}" | tee "${output}"
