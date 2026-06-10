#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

echo -e "\n === Collecting test results and metrics ===\n"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1090,SC1091
source "$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$SCRIPT_DIR"/../test.env)"

# shellcheck disable=SC1090,SC1091
source "$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$SCRIPT_DIR"/rhdh-setup/common.sh)"

ARTIFACT_DIR=$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "${ARTIFACT_DIR:-.artifacts}")
mkdir -p "${ARTIFACT_DIR}"

PROFILING_DIR=$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "${ARTIFACT_DIR}/profiling")
mkdir -p "${PROFILING_DIR}"

export TMP_DIR

TMP_DIR=$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "${TMP_DIR:-.tmp}")
mkdir -p "${TMP_DIR}"

export RHDH_NAMESPACE

RHDH_NAMESPACE=${RHDH_NAMESPACE:-rhdh-performance}
ENABLE_PROFILING="${ENABLE_PROFILING:-false}"
RHDH_INSTALL_METHOD="${RHDH_INSTALL_METHOD:-helm}"
NODEJS_PROFILING_DIR="${NODEJS_PROFILING_DIR:-/tmp}"
DOWNLOAD_ONLY="${DOWNLOAD_ONLY:-false}"
GATHER_MEMORY_PROFILE="${GATHER_MEMORY_PROFILE:-true}"
GATHER_CPU_PROFILE="${GATHER_CPU_PROFILE:-true}"

cli="oc"
clin="$cli -n $RHDH_NAMESPACE"

find_files_on_pod() {
    pod=$1
    container=$2
    dir=$3
    file_pattern=$4
    # shellcheck disable=SC2016
    $clin exec "$pod" -c "$container" -- /bin/bash -c 'f=$(find '"$dir"' -name '"$file_pattern"' -type f 2>/dev/null | sort); if [ -n "$f" ]; then echo $f; fi'
}

remote_file_size() {
    pod=$1
    container=$2
    remote_file=$3
    # shellcheck disable=SC2016
    $clin exec "$pod" -c "$container" -- /bin/bash -c 'f='"$(printf '%q' "$remote_file")"'; if [[ -f "$f" ]]; then stat -c%s "$f"; fi' 2>/dev/null || true
}

# Wait until all files matching a pattern exist and their sizes stop changing.
wait_for_remote_files_size_stable() {
    pod=$1
    container=$2
    dir=$3
    file_pattern=$4
    interval=${5:-5}
    prev_fingerprint=""

    while true; do
        # shellcheck disable=SC2016
        fingerprint=$($clin exec "$pod" -c "$container" -- /bin/bash -c 'find '"$dir"' -name '"$file_pattern"' -type f 2>/dev/null | sort | while read -r f; do stat -c"%n:%s" "$f"; done' | tr '\n' '|')

        if [[ -z "$fingerprint" ]]; then
            log_info "Waiting for $file_pattern files to appear on $pod in $dir"
            prev_fingerprint=""
            sleep "$interval"
            continue
        fi

        if [[ "$fingerprint" == "$prev_fingerprint" ]]; then
            log_info "Remote files stable on $pod: $file_pattern in $dir"
            return 0
        fi

        log_info "Remote files still changing on $pod: $file_pattern in $dir"
        prev_fingerprint="$fingerprint"
        sleep "$interval"
    done
}

download_files_from_pod() {
    pod=$1
    container=$2
    src_dir=$3
    file_pattern=$4
    dst_dir=$5
    files=$(find_files_on_pod "$pod" "$container" "$src_dir" "$file_pattern")
    for file in $files; do
        #$clin rsync "$pod":"$file" -c "$container" "$dst_dir" --strategy=tar
        dst_file="$dst_dir"/"$(basename "$file")"
        log_info "Downloading $file from $pod to $dst_file"
        $clin exec "$pod" -c "$container" -- /bin/bash -c 'cat '"$file"' | base64 -w0' | base64 -d >"$dst_file"
    done
}

if [ "$RHDH_INSTALL_METHOD" == "helm" ] && ${ENABLE_PROFILING}; then
    mapfile -t pods <<<"$($clin get pod -l app.kubernetes.io/component=backstage -o json | jq -rc '.items[].metadata.name')"
    if [ "$GATHER_MEMORY_PROFILE" == "true" ]; then
        if [ "$DOWNLOAD_ONLY" != "true" ]; then
            for pod in "${pods[@]}"; do
                log_info "Triggering heap snapshot on $pod (SIGUSR2 → node PID 1)"
                $clin exec "$pod" -c backstage-backend -- /bin/bash -c 'kill -s USR2 1'
            done
            for pod in "${pods[@]}"; do
                log_info "Waiting for heap snapshots on $pod to finish writing"
                wait_for_remote_files_size_stable "$pod" "backstage-backend" "$NODEJS_PROFILING_DIR" "*.heapsnapshot"
            done
        fi
        for pod in "${pods[@]}"; do
            PROFILING_DIR_PER_POD="${PROFILING_DIR}/$pod"
            mkdir -p "${PROFILING_DIR_PER_POD}"
            log_info "Collecting heap snapshot into ${PROFILING_DIR_PER_POD}"
            download_files_from_pod "$pod" "backstage-backend" "$NODEJS_PROFILING_DIR" "*.heapsnapshot" "${PROFILING_DIR_PER_POD}"
        done
    fi
    if [ "$GATHER_CPU_PROFILE" == "true" ]; then
        for pod in "${pods[@]}"; do
            PROFILING_DIR_PER_POD="${PROFILING_DIR}/$pod"
            mkdir -p "${PROFILING_DIR_PER_POD}"
            log_info "Collecting CPU profile into ${PROFILING_DIR_PER_POD}"
            download_files_from_pod "$pod" "backstage-backend" "$NODEJS_PROFILING_DIR" "*v8.log" "${PROFILING_DIR_PER_POD}"
        done
    fi
fi
