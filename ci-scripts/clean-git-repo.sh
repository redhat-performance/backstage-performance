#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1090,SC1091
source "$(readlink -m "$SCRIPT_DIR"/../test.env)"

GITHUB_TOKEN="$(cat /usr/local/ci-secrets/backstage-performance/github.token)"
GITHUB_ORG="$(cat /usr/local/ci-secrets/backstage-performance/github.org)"
GITHUB_REPO="$(cat /usr/local/ci-secrets/backstage-performance/github.repo)"
REPO_GIT="${GITHUB_REPO##*/}"
REPO="${REPO_GIT%%.git}"

response_headers=$(mktemp)
branches_list=$(mktemp)

curl_args='-s -H "Accept: application/vnd.github+json" -H "Authorization: token '$GITHUB_TOKEN'" -H "X-GitHub-Api-Version: 2022-11-28" -D '$response_headers

echo -n "Collecting list of branches in '${GITHUB_REPO}' repository to delete"
page=1
while true; do
    echo -n "."
    echo "$curl_args" "https://api.github.com/repos/$GITHUB_ORG/$REPO/branches?per_page=100&page=$page" | xargs curl | jq -r '.[].name' >>"$branches_list"

    if ! grep -q 'rel="next"' "$response_headers"; then
        break
    fi

    ((page++))
done

DRY_RUN=${DRY_RUN:-true}
echo " Found $(wc -l <"$branches_list") branches"
while read -r branch; do
    if [ "$branch" != "main" ]; then
        if [ "$DRY_RUN" == "false" ]; then
            echo "Deleting branch $branch"
            echo "$curl_args" -X DELETE "https://api.github.com/repos/$GITHUB_ORG/$REPO/git/refs/heads/$branch" | xargs curl
        else
            echo "[DRY-RUN] Would have deleted branch $branch"
        fi
    fi
done <"$branches_list"

echo "Branch cleanup completed."
