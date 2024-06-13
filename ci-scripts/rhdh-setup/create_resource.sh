#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1090,SC1091
source "$(readlink -m "$SCRIPT_DIR"/../../test.env)"

export TMP_DIR WORKDIR

POPULATION_CONCURRENCY=${POPULATION_CONCURRENCY:-10}
COMPONENT_SHARD_SIZE=${COMPONENT_SHARD_SIZE:-500}

TMP_DIR=${TMP_DIR:-$(readlink -m .tmp)}
mkdir -p "$TMP_DIR"
WORKDIR=$(readlink -m .)

kc_lockfile="$TMP_DIR/kc.lockfile"

keycloak_url() {
  f="$TMP_DIR/keycloak.url"
  exec 4>"$kc_lockfile"
  flock 4 || {
    echo "Failed to acquire lock"
    exit 1
  }

  if [ ! -f "$f" ]; then
    echo -n "https://$(oc get routes keycloak -n "${RHDH_NAMESPACE}" -o jsonpath='{.spec.host}')" >"$f"
  fi
  flock -u 4
  cat "$f"
}

bs_lockfile="$TMP_DIR/bs.lockfile"

backstage_url() {
  f="$TMP_DIR/backstage.url"
  exec 5>"$bs_lockfile"
  flock 5 || {
    echo "Failed to acquire lock"
    exit 1
  }
  if [ ! -f "$f" ]; then
    if [ "$INSTALL_METHOD" == "helm" ]; then
      rhdh_route="${RHDH_HELM_RELEASE_NAME}-${RHDH_HELM_CHART}"
    else
      rhdh_route="backstage-developer-hub"
    fi
    echo -n "https://$(oc get routes "${rhdh_route}" -n "${RHDH_NAMESPACE}" -o jsonpath='{.spec.host}')" >"$f"
  fi
  flock -u 5
  cat "$f"
}

create_per_grp() {
  echo "[INFO][$(date --utc -Ins)] Creating entity YAML files"
  varname=$2
  obj_count=${!varname}
  if [[ -z ${!varname} ]]; then
    echo "$varname is not set: Skipping $1 "
    exit 1
  fi
  local iter_count mod
  iter_count=$(echo "(${obj_count}/${GROUP_COUNT})" | bc)
  mod=$(echo "(${obj_count}%${GROUP_COUNT})" | bc)

  if [[ ! ${mod} -eq 0 ]]; then
    iter_count=$(echo "${iter_count}+1" | bc)
  fi
  indx=0
  shard_index=0
  for _ in $(seq 1 "${iter_count}"); do
    for g in $(seq 1 "${GROUP_COUNT}"); do
      indx=$((1 + indx))
      [[ ${obj_count} -lt $indx ]] && break
      $1 "$g" "$indx" "$shard_index"
      if [ "$(echo "(${indx}%${COMPONENT_SHARD_SIZE})" | bc)" == "0" ]; then
        shard_index=$((shard_index + 1))
      fi
    done
  done
  if [[ 'create_cmp' == "${1}" ]]; then clone_and_upload "component-*.yaml"; fi
  if [[ 'create_api' == "${1}" ]]; then clone_and_upload "api-*.yaml"; fi
}

clone_and_upload() {
  echo "[INFO][$(date --utc -Ins)] Uploading entities to GitHub"
  git_str="${GITHUB_USER}:${GITHUB_TOKEN}@github.com"
  base_name=$(basename "$GITHUB_REPO")
  git_dir=$TMP_DIR/${base_name}
  git_repo=${GITHUB_REPO//github.com/${git_str}}
  [[ -d "${git_dir}" ]] && rm -rf "${git_dir}"
  git clone "$git_repo" "$git_dir"
  cd "$git_dir" || return
  git config user.name "rhdh-performance-bot"
  git config user.email rhdh-performance-bot@redhat.com
  tmp_branch=$(mktemp -u XXXXXXXXXX)
  git checkout -b "$tmp_branch"
  mapfile -t files < <(find "$TMP_DIR" -name "$1")
  for filename in "${files[@]}"; do
    cp -vf "$filename" "$(basename "$filename")"
    git add "$(basename "$filename")"
  done
  git commit -a -m "commit objects"
  git push -f --set-upstream origin "$tmp_branch"
  cd ..
  sleep 5
  rhdh_token=$(curl -s -k "$(backstage_url)/api/auth/guest/refresh" | jq -r '.backstageIdentity.token')
  for filename in "${files[@]}"; do
    e_count=$(yq eval '.metadata.name | capture(".*-(?<value>[0-9]+)").value' "$filename" | tail -n 1)
    upload_url="${GITHUB_REPO%.*}/blob/${tmp_branch}/$(basename "$filename")"
    curl -k "$(backstage_url)/api/catalog/locations" -X POST -H 'Accept-Encoding: gzip, deflate, br' -H 'Authorization: Bearer '"$rhdh_token" -H 'Content-Type: application/json' --data-raw '{"type":"url","target":"'"${upload_url}"'"}'

    timeout_timestamp=$(date -d "300 seconds" "+%s")
    while true; do
      if [ "$(date "+%s")" -gt "$timeout_timestamp" ]; then
        echo "ERROR: Timeout waiting on entity count"
        exit 1
      else
        if [[ 'component-*.yaml' == "${1}" ]]; then b_count=$(curl -s -k "$(backstage_url)/api/catalog/entity-facets?facet=kind" -H 'Content-Type: application/json' -H 'Authorization: Bearer '"$rhdh_token" | jq -r '.facets.kind[] | select(.value == "Component")| .count'); fi
        if [[ 'api-*.yaml' == "${1}" ]]; then b_count=$(curl -s -k "$(backstage_url)/api/catalog/entity-facets?facet=kind" -H 'Content-Type: application/json' -H 'Authorization: Bearer '"$rhdh_token" | jq -r '.facets.kind[] | select(.value == "API")| .count'); fi
        if [[ $b_count -ge $e_count ]]; then break; fi
      fi
      echo "Waiting for the entity count ${e_count}"
      sleep 10s
    done
  done
  for filename in "${files[@]}"; do
    rm -vf "$filename"
  done
}

# shellcheck disable=SC2016
create_api() {
  export grp_indx=$1
  export api_indx=$2
  export shard_indx=${3:-0}
  envsubst '${grp_indx} ${api_indx}' <"$WORKDIR/template/component/api.template" >>"$TMP_DIR/api-$shard_indx.yaml"
}

# shellcheck disable=SC2016
create_cmp() {
  export grp_indx=$1
  export cmp_indx=$2
  export shard_indx=${3:-0}
  envsubst '${grp_indx} ${cmp_indx}' <"$WORKDIR/template/component/component.template" >>"$TMP_DIR/component-$shard_indx.yaml"
}

create_group() {
  token=$(get_token)
  groupname="group${0}"
  curl -s -k --location --request POST "$(keycloak_url)/auth/admin/realms/backstage/groups" \
    -H 'Content-Type: application/json' \
    -H 'Authorization: Bearer '"$token" \
    --data-raw '{"name": "'"${groupname}"'"}' |& tee -a "$TMP_DIR/create_group.log"
  echo "[INFO][$(date --utc -Ins)] Group $groupname created" >>"$TMP_DIR/create_group.log"
}

create_groups() {
  echo "Creating Groups in Keycloak"
  sleep 5
  seq 1 "${GROUP_COUNT}" | xargs -n1 -P"${POPULATION_CONCURRENCY}" bash -c 'create_group'
}

create_user() {
  token=$(get_token)
  grp=$(echo "${0}%${GROUP_COUNT}" | bc)
  [[ $grp -eq 0 ]] && grp=${GROUP_COUNT}
  username="test${0}"
  groupname="group${grp}"
  curl -s -k --location --request POST "$(keycloak_url)/auth/admin/realms/backstage/users" \
    -H 'Content-Type: application/json' \
    -H 'Authorization: Bearer '"$token" \
    --data-raw '{"firstName":"'"${username}"'","lastName":"tester", "email":"'"${username}"'@test.com","emailVerified":"true", "enabled":"true", "username":"'"${username}"'","groups":["/'"${groupname}"'"],"credentials":[{"type":"password","value":"'"${KEYCLOAK_USER_PASS}"'","temporary":false}]}' |& tee -a "$TMP_DIR/create_user.log"
  echo "[INFO][$(date --utc -Ins)] User $username ($groupname) created" >>"$TMP_DIR/create_user.log"
}

create_users() {
  echo "Creating Users in Keycloak"
  export GROUP_COUNT
  sleep 5
  seq 1 "${BACKSTAGE_USER_COUNT}" | xargs -n1 -P"${POPULATION_CONCURRENCY}" bash -c 'create_user'
}

token_lockfile="$TMP_DIR/token.lockfile"
log_token() {
  echo "[${2:-INFO}][$(date --utc -Ins)] $1" >>"$TMP_DIR/get_token.log"
}

log_token_info() {
  log_token "$1" "INFO"
}

log_token_err() {
  log_token "$1" "ERROR"
}

get_token() {
  token_file=$TMP_DIR/token.json
  while ! mkdir "$token_lockfile" 2>/dev/null; do
    sleep 0.5s
  done
  #shellcheck disable=SC2064
  trap "rm -rf $token_lockfile; exit" INT TERM EXIT HUP

  timeout_timestamp=$(date -d "60 seconds" "+%s")
  while [ ! -f "$token_file" ] || [ ! -s "$token_file" ] || [ "$(date +%s)" -gt "$(jq -rc '.expires_in_timestamp' "$token_file")" ]; do
    log_token_info "Refreshing keycloak token"
    if [ "$(date "+%s")" -gt "$timeout_timestamp" ]; then
      log_token_err "Timeout getting keycloak token"
      exit 1
    fi
    keycloak_pass=$(oc -n "${RHDH_NAMESPACE}" get secret credential-example-sso -o template --template='{{.data.ADMIN_PASSWORD}}' | base64 -d)
    if ! curl -s -k "$(keycloak_url)/auth/realms/master/protocol/openid-connect/token" -d username=admin -d "password=${keycloak_pass}" -d 'grant_type=password' -d 'client_id=admin-cli' | jq -r ".expires_in_timestamp = $(date -d '30 seconds' +%s)" >"$token_file"; then
      log_token_err "Unable to get token, re-attempting"
    fi
    sleep 5s
  done

  jq -rc '.access_token' "$token_file"
  rm -rf "$token_lockfile"
}

export -f keycloak_url backstage_url backstage_url get_token create_group create_user log_token log_token_info log_token_err
export kc_lockfile bs_lockfile token_lockfile
