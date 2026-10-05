#!/usr/bin/env bash
#
# Compare dynamic plugin OCI packages configured in this repo against
# metadata published in redhat-developer/rhdh-plugin-export-overlays.
# Plugins with no metadata YAML fall back to the published GHCR tag for
# the overlays Backstage version.
#
# Usage:
#   ./ci-scripts/check-plugins.sh
#
# Optional environment:
#   OVERLAYS_REPO  Git URL of the overlays repo
#                  (default: https://github.com/redhat-developer/rhdh-plugin-export-overlays.git)
#   OVERLAYS_REF   Git ref to compare against (default: main)
#   OVERLAYS_DIR   Existing overlays checkout to reuse instead of cloning
#
# Exit status:
#   0  no overlay plugin tag mismatches (missing/non-overlay plugins warn only)
#   1  at least one overlay plugin tag differs from remote
#   2  usage / setup error

set -o nounset
set -o errexit
set -o pipefail

OVERLAYS_REPO="${OVERLAYS_REPO:-https://github.com/redhat-developer/rhdh-plugin-export-overlays.git}"
OVERLAYS_REF="${OVERLAYS_REF:-main}"
OVERLAY_REGISTRY="ghcr.io/redhat-developer/rhdh-plugin-export-overlays"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

usage() {
    cat <<EOF
Usage: $(basename "$0") [-h]

Scan local dynamic plugin OCI packages and compare their tags with
rhdh-plugin-export-overlays metadata on GitHub. If a plugin has no
metadata YAML, the published GHCR tag is used instead.

Environment:
  OVERLAYS_REPO  Overlays git URL (default: $OVERLAYS_REPO)
  OVERLAYS_REF   Overlays git ref (default: $OVERLAYS_REF)
  OVERLAYS_DIR   Existing overlays checkout (skip clone)
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Parse an oci:// package reference into plugin<TAB>tag<TAB>image.
# Split tag/digest from the last path component so registry ports (host:port/...)
# are not treated as the image/tag boundary. Digest refs are stored as @sha256:...
# and are not version tags.
parse_oci_package() {
    local raw=$1
    local pkg name_ver plugin tag image digest
    pkg=$(sed -E 's/.*oci:\/\///; s/["'\''].*$//; s/[[:space:]].*$//' <<<"$raw")
    [[ -n "$pkg" ]] || return 1
    name_ver="${pkg##*/}"
    if [[ "$name_ver" == *@* ]]; then
        digest="${name_ver#*@}"
        name_ver="${name_ver%@*}"
    else
        digest=""
    fi
    if [[ "$name_ver" == *:* ]]; then
        plugin="${name_ver%%:*}"
        tag="${name_ver#*:}"
    else
        plugin="$name_ver"
        tag="-"
    fi
    if [[ -n "$digest" ]]; then
        tag="@${digest}"
    fi
    if [[ "$pkg" == */* ]]; then
        image="${pkg%/*}/$plugin"
    else
        image="$plugin"
    fi
    printf '%s\t%s\t%s\n' "$plugin" "$tag" "$image"
}

shorten_source() {
    local rel=$1
    rel="${rel#ci-scripts/rhdh-setup/template/backstage/}"
    printf '%s\n' "$rel"
}

shorten_sources() {
    local csv=${1//, /,}
    local out="" f
    local -a arr
    IFS=',' read -ra arr <<<"$csv"
    for f in "${arr[@]}"; do
        [[ -n "$out" ]] && out+=", "
        out+=$(shorten_source "$f")
    done
    printf '%s\n' "$out"
}

# Scan tracked YAML for active `package: oci://...` values (quoted or unquoted).
# Commented-out references are ignored.
scan_local_plugins() {
    local line file rest parsed
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        file="${line%%:*}"
        rest="${line#*:}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        [[ "$rest" == \#* ]] && continue
        parsed=$(parse_oci_package "$rest") || continue
        printf '%s\t%s\n' "$parsed" "$file"
    done < <(git -C "$REPO_ROOT" grep -I -H -E '^[[:space:]]*(-[[:space:]]+)?package:[[:space:]]*["'\'']?oci://' -- '*.yaml' '*.yml' || true)
}

clone_overlays() {
    local head expected
    if [[ -n "${OVERLAYS_DIR:-}" ]]; then
        if [[ ! -d "$OVERLAYS_DIR" ]]; then
            echo "OVERLAYS_DIR does not exist: $OVERLAYS_DIR" >&2
            exit 2
        fi
        overlays_dir=$(cd "$OVERLAYS_DIR" && pwd)
        if [[ "$(git -C "$overlays_dir" rev-parse --is-inside-work-tree 2>/dev/null)" != "true" ]]; then
            echo "OVERLAYS_DIR is not a git checkout: $overlays_dir" >&2
            exit 2
        fi
        if ! git -C "$overlays_dir" rev-parse --verify --quiet HEAD >/dev/null; then
            echo "OVERLAYS_DIR checkout is empty: $overlays_dir" >&2
            exit 2
        fi
        expected=$(git -C "$overlays_dir" rev-parse --verify --quiet "${OVERLAYS_REF}^{commit}" 2>/dev/null) || {
            echo "OVERLAYS_DIR does not contain ref '$OVERLAYS_REF'" >&2
            exit 2
        }
        head=$(git -C "$overlays_dir" rev-parse HEAD)
        if [[ "$head" != "$expected" ]]; then
            echo "OVERLAYS_DIR is not at ref '$OVERLAYS_REF' (HEAD=$head, $OVERLAYS_REF=$expected)" >&2
            exit 2
        fi
        if [[ -z "$(find "$overlays_dir" -type f -path '*/metadata/*.yaml' -print -quit)" ]]; then
            echo "OVERLAYS_DIR has no overlay metadata YAML files: $overlays_dir" >&2
            exit 2
        fi
        echo "Using existing overlays checkout: $overlays_dir"
        return
    fi

    overlays_dir="$tmp/overlays"
    echo "Cloning $OVERLAYS_REPO (ref $OVERLAYS_REF) ..."
    GIT_TERMINAL_PROMPT=0 git -c init.templateDir= clone --quiet --depth 1 --filter=blob:none --sparse --branch "$OVERLAYS_REF" \
        "$OVERLAYS_REPO" "$overlays_dir"
    git -C "$overlays_dir" sparse-checkout set --no-cone 'workspaces/*/metadata/*.yaml' >/dev/null
}

scan_remote_plugins() {
    local file rel line parsed
    while IFS= read -r -d '' file; do
        rel="${file#"$overlays_dir"/}"
        while IFS= read -r line; do
            parsed=$(parse_oci_package "$line") || continue
            printf '%s\t%s\n' "$parsed" "$rel"
        done < <(grep -E 'dynamicArtifact:[[:space:]]*' "$file" || true)
    done < <(find "$overlays_dir" -type f -path '*/metadata/*.yaml' -print0 2>/dev/null)
}

is_overlay_image() {
    local image=$1
    [[ "$image" == "$OVERLAY_REGISTRY/"* ]]
}

is_digest_ref() {
    [[ "$1" == @sha256:* || "$1" == @sha512:* ]]
}

# Most common bs_<backstage> prefix in overlay metadata (e.g. 1.54.6).
infer_overlays_bs_version() {
    awk -F '\t' 'NF >= 2 { print $2 }' "$remote_raw" |
        sed -n 's/^bs_\([0-9][0-9.]*\)__.*/\1/p' |
        sort | uniq -c | sort -nr |
        awk 'NR == 1 { print $2 }'
}

# When a plugin has no metadata YAML, use the published GHCR tag for the
# overlays Backstage version (same source used to catch oauth2-proxy drift).
ghcr_lookup_skipped_reason=""
lookup_ghcr_tag() {
    local plugin=$1
    local bs_ver=$2
    local local_tag=$3
    local tags matched suffix=""
    local -a missing_tools=()

    if ! command -v skopeo >/dev/null; then
        missing_tools+=(skopeo)
    fi
    if ! command -v jq >/dev/null; then
        missing_tools+=(jq)
    fi
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        if [[ -z "$ghcr_lookup_skipped_reason" ]]; then
            ghcr_lookup_skipped_reason="${missing_tools[*]}"
            echo "Warning: ${ghcr_lookup_skipped_reason} not available; skipping GHCR tag lookup. Overlay plugins without metadata YAML will be reported as MISSING." >&2
        fi
        return 1
    fi
    tags=$(skopeo list-tags "docker://${OVERLAY_REGISTRY}/${plugin}" 2>/dev/null | jq -r '.Tags[]? // empty') || return 1
    [[ -n "$tags" ]] || return 1

    if [[ "$local_tag" == *!* ]]; then
        suffix="!${local_tag#*!}"
        tags=$(grep -F "$suffix" <<<"$tags" || true)
        [[ -n "$tags" ]] || return 1
    fi

    if [[ -n "$bs_ver" ]]; then
        matched=$(grep -E "^bs_${bs_ver//./\\.}__" <<<"$tags" | sort -V | tail -n1 || true)
        [[ -n "$matched" ]] || return 1
        printf '%s\n' "$matched"
        return 0
    fi
    matched=$(grep -E '^bs_' <<<"$tags" | sort -V | tail -n1 || true)
    [[ -n "$matched" ]] || return 1
    printf '%s\n' "$matched"
}

sed_escape_re() {
    printf '%s' "$1" | sed 's/[][().^$*+?{|}\\]/\\&/g'
}

sed_escape_repl() {
    printf '%s' "$1" | sed 's/[&\\|]/\\&/g'
}

# Prefer a metadata tag for the overlays Backstage version. MATCH if the local
# tag is among those; otherwise use the newest applicable tag.
pick_remote_tag() {
    local plugin=$1
    local local_tag=$2
    local all=${remote_all[$plugin]:-}
    local applicable matched
    [[ -n "$all" ]] || return 1
    if [[ -n "${overlays_bs_version:-}" ]]; then
        applicable=$(grep -E "^bs_${overlays_bs_version//./\\.}__" <<<"$all" || true)
        [[ -n "$applicable" ]] || return 1
    else
        applicable=$all
    fi
    if grep -qxF -- "$local_tag" <<<"$applicable"; then
        printf '%s\n' "$local_tag"
        return 0
    fi
    matched=$(sort -V <<<"$applicable" | tail -n1 || true)
    [[ -n "$matched" ]] || return 1
    printf '%s\n' "$matched"
}

# Print copy-pasteable GNU sed -i commands that replace local tags with overlay tags.
print_mismatch_sed() {
    local plugin=$1
    local local_tag=$2
    local remote_tag=$3
    local files=$4
    local from to file files_csv
    local -a file_arr
    from=$(sed_escape_re "${plugin}:${local_tag}")
    to=$(sed_escape_repl "${plugin}:${remote_tag}")
    printf '# %s: %s -> %s\n' "$plugin" "$local_tag" "$remote_tag"
    printf "sed -i 's|%s|%s|g'" "$from" "$to"
    files_csv=${files//, /,}
    IFS=',' read -ra file_arr <<<"$files_csv"
    for file in "${file_arr[@]}"; do
        [[ -n "$file" ]] || continue
        printf ' \\\n  %s' "$file"
    done
    printf '\n'
}

overlays_dir=""
clone_overlays

overlays_commit=$(git -C "$overlays_dir" rev-parse --short HEAD 2>/dev/null || echo "unknown")

local_raw="$tmp/local.tsv"
remote_raw="$tmp/remote.tsv"
overlay_rows="$tmp/overlay.tsv"
other_rows="$tmp/other.tsv"

scan_local_plugins | sort -u >"$local_raw"
scan_remote_plugins | sort -u >"$remote_raw"

if [[ ! -s "$local_raw" ]]; then
    echo "No local dynamic plugin packages found under $REPO_ROOT" >&2
    exit 2
fi

echo
echo "Local scan : $REPO_ROOT"
echo "Overlays   : $OVERLAYS_REPO"
echo "Ref        : $OVERLAYS_REF ($overlays_commit)"
echo

declare -A remote_all=()
declare -A remote_extra=()
while IFS=$'\t' read -r plugin tag _image src; do
    if [[ -z "${remote_all[$plugin]:-}" ]]; then
        remote_all["$plugin"]=$tag
    elif [[ $'\n'"${remote_all[$plugin]}"$'\n' != *$'\n'"$tag"$'\n'* ]]; then
        remote_extra["$plugin"]="${remote_extra[$plugin]:-}${remote_extra[$plugin]:+, }${tag} ($src)"
        remote_all["$plugin"]+=$'\n'$tag
    fi
done <"$remote_raw"

declare -A local_files=()
declare -A local_image=()
while IFS=$'\t' read -r plugin tag image src; do
    key="$plugin	$tag	$image"
    local_image["$key"]=$image
    if [[ -z "${local_files[$key]:-}" ]]; then
        local_files["$key"]=$src
    else
        local_files["$key"]="${local_files[$key]}, $src"
    fi
done <"$local_raw"

overlays_bs_version=$(infer_overlays_bs_version)
declare -A remote_from_ghcr=()

header=$'PLUGIN\tLOCAL\tREMOTE\tSTATUS\tSOURCE'
printf '%s\n' "$header" >"$overlay_rows"
printf '%s\n' "$header" >"$other_rows"

match=0
mismatch=0
missing=0
skipped=0
mismatch_seds="$tmp/mismatch-sed.sh"

while IFS=$'\t' read -r plugin tag image; do
    [[ -n "$plugin" ]] || continue
    key="$plugin	$tag	$image"
    src=${local_files[$key]:-}
    image=${local_image[$key]:-}
    remote=""
    status=""
    dest=$other_rows

    if is_overlay_image "$image"; then
        dest=$overlay_rows
        if is_digest_ref "$tag"; then
            remote=$(grep -E '^@(sha256|sha512):' <<<"${remote_all[$plugin]:-}" | tail -n1 || true)
            if [[ -n "$remote" ]]; then
                if [[ "$tag" == "$remote" ]]; then
                    status="MATCH"
                    match=$((match + 1))
                else
                    status="MISMATCH"
                    mismatch=$((mismatch + 1))
                fi
            else
                remote="DIGEST"
                status="DIGEST"
                skipped=$((skipped + 1))
            fi
        elif ! remote=$(pick_remote_tag "$plugin" "$tag"); then
            remote=""
            if ghcr_tag=$(lookup_ghcr_tag "$plugin" "$overlays_bs_version" "$tag"); then
                remote=$ghcr_tag
                remote_from_ghcr["$plugin"]=1
            fi
        fi
        if [[ -z "$status" && -n "$remote" ]]; then
            if [[ "$tag" == "$remote" ]]; then
                status="MATCH"
                match=$((match + 1))
            else
                status="MISMATCH"
                mismatch=$((mismatch + 1))
                print_mismatch_sed "$plugin" "$tag" "$remote" "$src" >>"$mismatch_seds"
            fi
        elif [[ -z "$status" ]]; then
            remote="NOT FOUND"
            status="MISSING"
            missing=$((missing + 1))
        fi
    else
        remote="-"
        status="WARNING"
        skipped=$((skipped + 1))
    fi

    printf '%s\t%s\t%s\t%s\t%s\n' "$plugin" "$tag" "$remote" "$status" "$(shorten_sources "$src")" >>"$dest"
done < <(cut -f1,2,3 "$local_raw" | sort -u)

echo "SOURCE paths are relative to ci-scripts/rhdh-setup/template/backstage/"
echo
if [[ $(wc -l <"$overlay_rows") -gt 1 ]]; then
    echo "=== Overlay plugins ==="
    column -t -s $'\t' "$overlay_rows"
    echo
fi
if [[ $(wc -l <"$other_rows") -gt 1 ]]; then
    echo "Warning: the following OCI packages are not part of rhdh-plugin-export-overlays (ignored for pass/fail):"
    column -t -s $'\t' "$other_rows"
    echo
fi

echo "Summary: $match match, $mismatch mismatch, $missing missing, $skipped warning (not an overlays plugin)"

if [[ ${#remote_from_ghcr[@]} -gt 0 ]]; then
    echo
    echo "Note: no overlay metadata YAML for these plugins; remote tag taken from GHCR (bs_${overlays_bs_version:-\?}):"
    for plugin in "${!remote_from_ghcr[@]}"; do
        echo "  $plugin"
    done
fi

if [[ ${#remote_extra[@]} -gt 0 ]]; then
    echo
    echo "Warning: multiple remote tags found for:"
    for plugin in "${!remote_extra[@]}"; do
        echo "  $plugin: ${remote_all[$plugin]//$'\n'/, }; also ${remote_extra[$plugin]}"
    done
fi

if [[ $missing -gt 0 ]]; then
    echo
    echo "Warning: $missing overlay plugin(s) have no remote tag in metadata or GHCR (ignored for pass/fail)"
    if [[ -n "$ghcr_lookup_skipped_reason" ]]; then
        echo "Warning: GHCR lookup was skipped because ${ghcr_lookup_skipped_reason} is not available"
    fi
fi

if [[ $mismatch -gt 0 ]]; then
    echo
    echo "=== Suggested bash commands to align with overlay versions ==="
    cat "$mismatch_seds"
    exit 1
fi
exit 0
