#!/usr/bin/bash

set -eu
set -o pipefail

# Purpose of this tool is to generate a error report CSV from error-report.txt
# artifact created by `/test mvp-scalability` job. It relies on set of regexp
# to group similar errors to same buckets.
#
# To use it, just pass error-report.txt download link as a parameter:
#
#     $ ci-scripts/helper-error-report.sh https://gcsweb-ci.apps.ci.l2s4.p1.openshiftapps.com/.../error-report.txt

log_url="$1"

error_unknown=0
error_504=0
error_503=0
error_502=0
error_remoteclose=0

heading=""
final_csv=""

function cleanup_errors() {
    error_504=0
    error_503=0
    error_502=0
    error_remoteclose=0
    error_unknown=0
}

function show_errors() {
    echo "=== $heading ==="
    echo "504 Server Error: Gateway Time-out for url: $error_504"
    echo "503 Server Error: Service Unavailable for url: $error_503"
    echo "502 Server Error: Bad Gateway for url: $error_502"
    echo "Remote end closed connection without response: $error_remoteclose"
    echo "Not recognized error: $error_unknown"
    final_csv="${final_csv}${heading},${log_url},${error_504},${error_503},${error_502},${error_remoteclose},${error_unknown}\n"
}

# Why this fifo? See https://jhutar.blogspot.com/2024/12/bash-while-read-line-without-subshell.html
trap 'rm -rf "$TMPFIFODIR"' EXIT
TMPFIFODIR=$( mktemp -d )
mkfifo "$TMPFIFODIR/mypipe"
###cat /tmp/error-report.txt > $TMPFIFODIR/mypipe &
curl -s "$log_url" > "$TMPFIFODIR/mypipe" &

while IFS=$'\n' read -r line; do
    case "$line" in
        \[*)
            [[ -n "$heading" ]] && show_errors
            heading="$line"
            cleanup_errors
        ;;
        *"504 Server Error: Gateway Time-out for url: "*)
            # shellcheck disable=SC2206
            numbers=( ${line//[!0-9]/ } )
            count=${numbers[0]}
            (( error_504+=count ))
        ;;
        *"503 Server Error: Service Unavailable for url: "*)
            # shellcheck disable=SC2206
            numbers=( ${line//[!0-9]/ } )
            count=${numbers[0]}
            (( error_503+=count ))
        ;;
        *"502 Server Error: Bad Gateway for url: "*)
            # shellcheck disable=SC2206
            numbers=( ${line//[!0-9]/ } )
            count="${numbers[0]}"
            (( error_502+=count ))
        ;;
        *"Remote end closed connection without response"*)
            # shellcheck disable=SC2206
            numbers=( ${line//[!0-9]/ } )
            count="${numbers[0]}"
            (( error_remoteclose+=count ))
        ;;
        "---"* | "" | "# occurrences"* | "Error report" | "No errors found!")
            true
        ;;
        *)
            echo "What shall we do with a drunken sailor? '$line'"
            (( error_unknown+=1 ))
        ;;
    esac
done < "$TMPFIFODIR/mypipe"

show_errors

echo -e "\nIn CSV form:\n"
echo "Scenario,Log,504 Server Error: Gateway Time-out for url: ...,503 Server Error: Service Unavailable for url: ...,502 Server Error: Bad Gateway for url: ...,Remote end closed connection without response,Not recognized error"
echo -e "$final_csv"
