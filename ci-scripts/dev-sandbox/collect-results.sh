#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1090,SC1091
source "$(readlink -m "$SCRIPT_DIR/../../test.env")"

rootdir=$(readlink -m "$SCRIPT_DIR/../..")

export ARTIFACT_DIR
ARTIFACT_DIR="${ARTIFACT_DIR:-"$rootdir/.artifacts"}"

export TMP_DIR
TMP_DIR=$(readlink -m "${TMP_DIR:-"$rootdir/.tmp"}")
mkdir -p "${TMP_DIR}"

out=$ARTIFACT_DIR/dev-sandbox/summary.csv
rm -rvf "$out"
while read -r baseline_csv; do
    while read -r metrics; do
        while IFS="," read -r -a tokens; do
            metric="${tokens[0]}"
            echo -n "${metric}" >>"$out"
            for run_csv in $(find "$ARTIFACT_DIR/dev-sandbox" -type f -regex '.*\(run[0-9]*\|baseline\).csv' | sort -V); do
                # shellcheck disable=SC2001
                run_id=$(sed -e 's,.*\(run[0-9]*\|baseline\).csv,\1,g' <<<"$run_csv")
                if [ "$metric" == "Item" ]; then
                    echo -n ",$run_id" >>"$out"
                else
                    echo -n ",$(grep "$metric" "$run_csv" | sed -e 's/.*,\(.*\)/\1/g')" >>"$out"
                fi
            done
            echo >>"$out"
        done <<<"$metrics"
    done <"$baseline_csv"
done <<<"$(find "${ARTIFACT_DIR}/dev-sandbox/" -name '*baseline.csv')"

while read -r baseline_counts_csv; do
    while read -r metrics; do
        while IFS="," read -r -a tokens; do
            metric="${tokens[0]}"
            echo -n "${metric}" >>"$out"
            for run_csv in $(find "$ARTIFACT_DIR/dev-sandbox" -type f -regex '.*\(run[0-9]*\|baseline\)-counts-post.csv' | sort -V); do
                echo -n ",$(grep "$metric" "$run_csv" | sed -e 's/.*,\(.*\)/\1/g')" >>"$out"
            done
            echo >>"$out"
        done <<<"$metrics"
    done <"$baseline_counts_csv"
done <<<"$(find "${ARTIFACT_DIR}/dev-sandbox/" -name '*baseline-counts-post.csv')"
