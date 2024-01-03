#!/bin/bash

export TMP_DIR WORKDIR

POPULATION_CONCURRENCY=${POPULATION_CONCURRENCY:-10}

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
  set +x
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
    echo -n "https://$(oc get routes "${RHDH_HELM_RELEASE_NAME}-developer-hub" -n "${RHDH_NAMESPACE}" -o jsonpath='{.spec.host}')" >"$f"
  fi
  flock -u 5
  cat "$f"
}

create_per_grp() {
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
  for _ in $(seq 1 "${iter_count}"); do
    for g in $(seq 1 "${GROUP_COUNT}"); do
      indx=$((1 + indx))
      [[ ${obj_count} -lt $indx ]] && break
      $1 "$g" "$indx"
    done
  done
}

clone_and_upload() {
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
  mv -vf "$1" .
  filename=$(basename "$1")
  git add "$filename"
  git commit -a -m "commit objects"
  git push -f --set-upstream origin "$tmp_branch"
  cd ..
  sleep 5
  upload_url="${GITHUB_REPO%.*}/blob/${tmp_branch}/${filename}"
  curl -k "$(backstage_url)/api/catalog/locations" -X POST -H 'Accept-Encoding: gzip, deflate, br' -H 'Content-Type: application/json' --data-raw '{"type":"url","target":"'"${upload_url}"'"}'
}

# shellcheck disable=SC2016
create_api() {
  export grp_indx=$1
  export api_indx=$2
  envsubst '${grp_indx} ${api_indx}' <"$WORKDIR/template/component/api.template" >>"$TMP_DIR/api.yaml"
}

# shellcheck disable=SC2016
create_cmp() {
  export grp_indx=$1
  export cmp_indx=$2
  envsubst '${grp_indx} ${cmp_indx}' <"$WORKDIR/template/component/component.template" >>"$TMP_DIR/component.yaml"
}

create_group() {
  token=$(get_token)
  groupname="group${0}"
  curl -s -k --location --request POST "$(keycloak_url)/auth/admin/realms/backstage/groups" \
    -H 'Content-Type: application/json' \
    -H 'Authorization: Bearer '"$token" \
    --data-raw '{"name": "'"${groupname}"'"}'
}

create_groups() {
  echo "Creating Groups in Keycloak"
  refresh_pid=$!
  sleep 5
  seq 1 "${GROUP_COUNT}" | xargs -n1 -P"${POPULATION_CONCURRENCY}" bash -c 'create_group'
  kill $refresh_pid
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
    --data-raw '{"firstName":"'"${username}"'","lastName":"tester", "email":"'"${username}"'@test.com", "enabled":"true", "username":"'"${username}"'","groups":["/'"${groupname}"'"]}'
}

create_users() {
  echo "Creating Users in Keycloak"
  export GROUP_COUNT
  refresh_pid=$!
  sleep 5
  seq 1 "${BACKSTAGE_USER_COUNT}" | xargs -n1 -P"${POPULATION_CONCURRENCY}" bash -c 'create_user'
  kill $refresh_pid
}

token_lockfile="$TMP_DIR/token.lockfile"

get_token() {
  token_file=$TMP_DIR/token.json
  exec 3>"$token_lockfile"
  flock 3 || {
    echo "Failed to acquire lock"
    exit 1
  }
  if [ ! -f "$token_file" ] || [ ! -s "$token_file" ] || [ "$(date +%s)" -gt "$(jq -rc '.expires_in_timestamp' "$token_file")" ]; then
    keycloak_pass=$(oc -n "${RHDH_NAMESPACE}" get secret credential-example-sso -o template --template='{{.data.ADMIN_PASSWORD}}' | base64 -d)
    curl -s -k "$(keycloak_url)/auth/realms/master/protocol/openid-connect/token" -d username=admin -d "password=${keycloak_pass}" -d 'grant_type=password' -d 'client_id=admin-cli' | jq -r ".expires_in_timestamp = $(date -d '30 seconds' +%s)" >"$token_file"
  fi
  flock -u 3
  jq -rc '.access_token' "$token_file"
}

export -f keycloak_url backstage_url backstage_url get_token create_group create_user
export kc_lockfile bs_lockfile token_lockfile
