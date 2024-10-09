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

COOKIE="$TMP_DIR/cookie.jar"

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
    if [ "$RHDH_INSTALL_METHOD" == "helm" ]; then
      rhdh_route="${RHDH_HELM_RELEASE_NAME}-${RHDH_HELM_CHART}"
    else
      if [ "$AUTH_PROVIDER" == "keycloak" ]; then
        rhdh_route="rhdh"
      else
        rhdh_route="backstage-developer-hub"
      fi
    fi
    echo -n "https://$(oc get routes "${rhdh_route}" -n "${RHDH_NAMESPACE}" -o jsonpath='{.spec.host}')" >"$f"
  fi
  flock -u 5
  cat "$f"
}

create_per_grp() {
  log_info "Creating entity YAML files"
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
  log_info "Uploading entities to GitHub"
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
  for filename in "${files[@]}"; do
    e_count=$(yq eval '.metadata.name | capture(".*-(?P<value>[0-9]+)").value' "$filename" | tail -n 1)
    upload_url="${GITHUB_REPO%.*}/blob/${tmp_branch}/$(basename "$filename")"
    log_info "Uploading entities from $upload_url"
    ACCESS_TOKEN=$(get_token "rhdh")
    curl -k "$(backstage_url)/api/catalog/locations" --cookie "$COOKIE" --cookie-jar "$COOKIE" -X POST -H 'Accept-Encoding: gzip, deflate, br' -H 'Authorization: Bearer '"$ACCESS_TOKEN" -H 'Content-Type: application/json' --data-raw '{"type":"url","target":"'"${upload_url}"'"}'

    timeout=1800
    timeout_timestamp=$(date -d "$timeout seconds" "+%s")
    last_count=-1
    while true; do
      if [ "$(date "+%s")" -gt "$timeout_timestamp" ]; then
        log_error "Timeout waiting on entity count"
        exit 1
      else
        ACCESS_TOKEN=$(get_token "rhdh")
        if [[ 'component-*.yaml' == "${1}" ]]; then b_count=$(curl -s -k "$(backstage_url)/api/catalog/entity-facets?facet=kind" --cookie "$COOKIE" --cookie-jar "$COOKIE" -H 'Content-Type: application/json' -H 'Authorization: Bearer '"$ACCESS_TOKEN" | tee -a "$TMP_DIR/get_component_count.log" | jq -r '.facets.kind[] | select(.value == "Component")| .count'); fi
        if [[ 'api-*.yaml' == "${1}" ]]; then b_count=$(curl -s -k "$(backstage_url)/api/catalog/entity-facets?facet=kind" --cookie "$COOKIE" --cookie-jar "$COOKIE" -H 'Content-Type: application/json' -H 'Authorization: Bearer '"$ACCESS_TOKEN" | tee -a "$TMP_DIR/get_api_count.log" | jq -r '.facets.kind[] | select(.value == "API")| .count'); fi
        if [[ "$last_count" != "$b_count" ]] && [[ $last_count -ge 0 ]]; then # reset the timeout if current count changes
          log_info "The current count changed, resetting entity waiting timeout to $timeout seconds"
          timeout_timestamp=$(date -d "$timeout seconds" "+%s")
          last_count=$b_count
        fi
        if [[ $b_count -ge $e_count ]]; then
          log_info "The entity count reached expected value ($b_count)"
          break
        fi
      fi
      log_info "Waiting for the entity count to be ${e_count} (current: ${b_count})"
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
  max_attempts=5
  attempt=1
  while ((attempt <= max_attempts)); do
    token=$(get_token)
    groupname="g${0}"
    response="$(curl -s -k --location --request POST "$(keycloak_url)/auth/admin/realms/backstage/groups" \
      -H 'Content-Type: application/json' \
      -H 'Authorization: Bearer '"$token" \
      --data-raw '{"name": "'"${groupname}"'"}' 2>&1)"
    if [ "${PIPESTATUS[0]}" -eq 0 ] && ! echo "$response" | grep -q 'error' >&/dev/null; then
      log_info "Group $groupname created" >>"$TMP_DIR/create_group.log"
      return
    else
      log_warn "Unable to create the $groupname group at $attempt. attempt. [$response]. Trying again up to $max_attempts times." >>"$TMP_DIR/create_group.log"
      ((attempt++))
    fi
  done
  if [[ $attempt -gt $max_attempts ]]; then
    log_error "Unable to create the $groupname group in $max_attempts attempts, giving up!" |& tee -a "$TMP_DIR/create_group.log"
  fi
}

export RBAC_POLICY_ALL_GROUPS_ADMIN="all_groups_admin" #default
export RBAC_POLICY_STATIC="static"

create_rbac_policy() {
  policy="${1:-$RBAC_POLICY_ALL_GROUPS_ADMIN}"
  log_info "Generating RBAC policy: $policy"
  case $policy in
  "$RBAC_POLICY_ALL_GROUPS_ADMIN")
    for i in $(seq 1 "$GROUP_COUNT"); do
      echo "    g, group:default/g${i}, role:default/a" >>"$TMP_DIR/group-rbac.yaml"
    done
    ;;
  "$RBAC_POLICY_STATIC")
    for i in $(seq 1 "${RBAC_POLICY_SIZE:-$GROUP_COUNT}"); do
      echo "    g, group:default/g${i}, role:default/a" >>"$TMP_DIR/group-rbac.yaml"
    done
    ;;
  \?)
    log_error "Invalid RBAC policy: ${policy}"
    exit 1
    ;;
  esac

}

create_groups() {
  log_info "Creating Groups in Keycloak"
  sleep 5
  seq 1 "${GROUP_COUNT}" | xargs -n1 -P"${POPULATION_CONCURRENCY}" bash -c 'create_group'
}

create_user() {
  max_attempts=5
  attempt=1
  while ((attempt <= max_attempts)); do
    token=$(get_token)
    grp=$(echo "${0}%${GROUP_COUNT}" | bc)
    [[ $grp -eq 0 ]] && grp=${GROUP_COUNT}
    username="t${0}"
    groupname="g${grp}"
    response="$(curl -s -k --location --request POST "$(keycloak_url)/auth/admin/realms/backstage/users" \
      -H 'Content-Type: application/json' \
      -H 'Authorization: Bearer '"$token" \
      --data-raw '{"firstName":"'"${username}"'","lastName":"tester", "email":"'"${username}"'@test.com","emailVerified":"true", "enabled":"true", "username":"'"${username}"'","groups":["/'"${groupname}"'"],"credentials":[{"type":"password","value":"'"${KEYCLOAK_USER_PASS}"'","temporary":false}]}' 2>&1)"
    if [ "${PIPESTATUS[0]}" -eq 0 ] && ! echo "$response" | grep -q 'error' >&/dev/null; then
      log_info "User $username ($groupname) created" >>"$TMP_DIR/create_user.log"
      return
    else
      log_warn "Unable to create the $username user at $attempt. attempt. [$response].  Trying again up to $max_attempts times." >>"$TMP_DIR/create_user.log"
      ((attempt++))
    fi
  done
  if [[ $attempt -gt $max_attempts ]]; then
    log_error "Unable to create the $username user in $max_attempts attempts, giving up!" |& tee -a "$TMP_DIR/create_user.log"
  fi
}

create_users() {
  log_info "Creating Users in Keycloak"
  export GROUP_COUNT
  sleep 5
  seq 1 "${BACKSTAGE_USER_COUNT}" | xargs -n1 -P"${POPULATION_CONCURRENCY}" bash -c 'create_user'
}

token_lockfile="$TMP_DIR/token.lockfile"
log() {
  echo "{\"level\":\"${2:-info}\",\"ts\":\"$(date --utc -Ins)\",\"message\":\"$1\"}"
}

log_info() {
  log "$1" "info"
}

log_warn() {
  log "$1" "warn"
}

log_error() {
  log "$1" "error"
}

log_token() {
  log "$1" "$2" >>"$TMP_DIR/get_token.log"
}

log_token_info() {
  log_token "$1" "info"
}

log_token_err() {
  log_token "$1" "error"
}

keycloak_token() {
  curl -s -k "$(keycloak_url)/auth/realms/master/protocol/openid-connect/token" -d username=admin -d "password=$1" -d 'grant_type=password' -d 'client_id=admin-cli' | jq -r ".expires_in_timestamp = $(date -d '30 seconds' +%s)"
}

rhdh_token() {
  REDIRECT_URL="$(backstage_url)/oauth2/callback"
  REFRESH_URL="$(backstage_url)/api/auth/oauth2Proxy/refresh"
  USERNAME="guru"
  PASSWORD=$(oc -n "${RHDH_NAMESPACE}" get secret perf-test-secrets -o template --template='{{.data.keycloak_user_pass}}' | base64 -d)
  REALM="backstage"
  CLIENTID="backstage"

  if [[ "${AUTH_PROVIDER}" != "keycloak" ]]; then
    ACCESS_TOKEN=$(curl -s -k --cookie "$COOKIE" --cookie-jar "$COOKIE" "$(backstage_url)/api/auth/guest/refresh" | jq -r ".backstageIdentity" | jq -r ".expires_in_timestamp = $(date -d '50 minutes' +%s)")
    echo "$ACCESS_TOKEN"
    return
  fi

  LOGIN_URL=$(curl -I -k -sSL --cookie "$COOKIE" --cookie-jar "$COOKIE" "$REFRESH_URL")
  state=$(echo "$LOGIN_URL" | grep -oP 'state=\K[^ ]+' | sed 's/%2F/\//g;s/%3A/:/g')

  AUTH_URL=$(curl -k -sSL --get --cookie "$COOKIE" --cookie-jar "$COOKIE" \
    --data-urlencode "client_id=${CLIENTID}" \
    --data-urlencode "state=${state}" \
    --data-urlencode "redirect_uri=${REDIRECT_URL}" \
    --data-urlencode "scope=openid email profile" \
    --data-urlencode "response_type=code" \
    "$(keycloak_url)/auth/realms/$REALM/protocol/openid-connect/auth" | grep -oP 'action="\K[^"]+')

  execution=$(echo "$AUTH_URL" | grep -oP 'execution=\K[^&]+')
  tab_id=$(echo "$AUTH_URL" | grep -oP 'tab_id=\K[^&]+')
  # shellcheck disable=SC2001
  AUTHENTICATE_URL=$(echo "$AUTH_URL" | sed -e 's/\&amp;/\&/g')

  CODE_URL=$(curl -k -sS --cookie "$COOKIE" --cookie-jar "$COOKIE" \
    --data-raw "username=${USERNAME}&password=${PASSWORD}&credentialId=" \
    --data-urlencode "client_id=${CLIENTID}" \
    --data-urlencode "tab_id=${tab_id}" \
    --data-urlencode "execution=${execution}" \
    --write-out "%{REDIRECT_URL}" \
    "$AUTHENTICATE_URL")

  code=$(echo "$CODE_URL" | grep -oP 'code=\K[^"]+')
  session_state=$(echo "$CODE_URL" | grep -oP 'session_state=\K[^&]+')

  # shellcheck disable=SC2001
  CODE_URL=$(echo "$CODE_URL" | sed -e 's/\&amp;/\&/g')
  ACCESS_TOKEN=$(curl -k -sSL --cookie "$COOKIE" --cookie-jar "$COOKIE" \
    --data-urlencode "code=$code" \
    --data-urlencode "session_state=$session_state" \
    --data-urlencode "state=$state" \
    "$CODE_URL" | tee -a "$TMP_DIR/get_rhdh_token.log" | jq -r ".backstageIdentity" | jq -r ".expires_in_timestamp = $(date -d '30 minutes' +%s)")
  echo "$ACCESS_TOKEN"
}

get_token() {
  service=$1
  if [[ ${service} == 'rhdh' ]]; then
    token_file="$TMP_DIR/rhdh_token.json"
    token_field=".token"
    token_type="RHDH"
    token_timeout="3600"
  else
    token_file="$TMP_DIR/keycloak_token.json"
    token_field=".access_token"
    token_type="Keycloak"
    token_timeout="60"
  fi
  while ! mkdir "$token_lockfile" 2>/dev/null; do
    sleep 0.5s
  done
  #shellcheck disable=SC2064
  trap "rm -rf $token_lockfile; exit" INT TERM EXIT HUP

  timeout_timestamp=$(date -d "$token_timeout seconds" "+%s")
  while [ ! -f "$token_file" ] || [ ! -s "$token_file" ] || [ -z "$(jq -rc '.expires_in_timestamp' "$token_file")" ] || [ "$(date +%s)" -gt "$(jq -rc '.expires_in_timestamp' "$token_file")" ] || [ "$(jq -rc "$token_field" "$token_file")" == "null" ]; do
    if [ "$(date "+%s")" -gt "$timeout_timestamp" ]; then
      log_token_err "Timeout getting $token_type token"
      exit 1
    fi
    log_token_info "Refreshing $token_type token"
    if [[ ${service} == 'rhdh' ]]; then
      [[ -f "$token_file" ]] && rm -rf "$token_file" && rm -rf "$TMP_DIR/cookie.jar"
      if ! rhdh_token >"$token_file" || [ "$(jq -rc "$token_field" "$token_file")" == "null" ]; then
        log_token_err "Unable to get $token_type token, re-attempting"
      fi
    else
      keycloak_pass=$(oc -n "${RHDH_NAMESPACE}" get secret credential-rhdh-sso -o template --template='{{.data.ADMIN_PASSWORD}}' | base64 -d)
      if ! keycloak_token "$keycloak_pass" >"$token_file"; then
        log_token_err "Unable to get $token_type token, re-attempting"
      fi
    fi
    sleep 5s
  done

  jq -rc "$token_field" "$token_file"
  rm -rf "$token_lockfile"
}

export -f keycloak_url backstage_url get_token keycloak_token rhdh_token create_rbac_policy create_group create_user log log_info log_warn log_error log_token log_token_info log_token_err
export kc_lockfile bs_lockfile token_lockfile
