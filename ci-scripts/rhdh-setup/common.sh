#!/bin/bash

TMP_DIR=${TMP_DIR:-$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' .tmp)}
mkdir -p "$TMP_DIR"

cli="oc"

log() {
  echo "{\"level\":\"${2:-info}\",\"ts\":\"$(date -u -Ins)\",\"message\":\"$1\"}"
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

wait_and_approve_install_plans() {
  namespace=${1:-namespace}
  initial_timeout=${2:-300}
  component_prefix=${3:-}
  description=${4:-"install plans in $namespace"}
  timeout_timestamp=$(python3 -c "from datetime import datetime, timedelta; t_add=int('$initial_timeout'); print(int((datetime.now() + timedelta(seconds=t_add)).timestamp()))")
  interval=10

  log_info "Waiting for unapproved install plans in $namespace namespace..."

  # Wait for install plans to appear with timeout
  install_plans=""
  for ((i = 0; i < initial_timeout; i += interval)); do
    install_plans=$($cli get installplan -n "$namespace" --sort-by=.metadata.creationTimestamp -o json | jq -r --arg prefix "$component_prefix" '.items[] | select(any(.spec.clusterServiceVersionNames[]; startswith($prefix))) | select(.spec.approved == false) | .metadata.name' 2>/dev/null)

    echo "install_plans: $install_plans"
    if [ -n "$install_plans" ]; then
      break
    fi

    if [ "$(date "+%s")" -gt "$timeout_timestamp" ]; then
      log_error "Timeout waiting for $description"
      exit 1
    fi

    log_info "Waiting ${interval}s for $description..."
    sleep "$interval"
  done

  # Approve each install plan found
  if [ -n "$install_plans" ]; then
    log_info "Found unapproved install plans in $namespace namespace, approving all..."
    for install_plan in $install_plans; do
      log_info "Approving install plan '$install_plan'..."
      $cli patch installplan "$install_plan" -n "$namespace" --type merge --patch '{"spec":{"approved":true}}'
    done
    return $?
  else
    log_error "No unapproved install plans found in $namespace namespace within timeout"
    exit 1
  fi
}

export -f log_info log_warn log_error log_token log_token_info log_token_err wait_and_approve_install_plans
