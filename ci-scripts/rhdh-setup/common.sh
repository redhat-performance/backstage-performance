#!/bin/bash

TMP_DIR=${TMP_DIR:-$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' .tmp)}
mkdir -p "$TMP_DIR"

cli="oc"

log() {
  echo -e "\n{\"level\":\"${2:-info}\",\"ts\":\"$(date -u -Ins)\",\"message\":\"$1\"}"
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

wait_to_exist() {
    namespace=${1:-${RHDH_NAMESPACE}}
    resource=${2:-deployment}
    name=${3:-name}
    initial_timeout=${4:-300}
    rn=$resource/$name
    description=${5:-"*$rn*"}
    timeout_timestamp=$(python3 -c "from datetime import datetime, timedelta; t_add=int('$initial_timeout'); print(int((datetime.now() + timedelta(seconds=t_add)).timestamp()))")

    interval=10s
    while ! /bin/bash -c "$cli -n $namespace get $resource -o name | grep $name"; do
        if [ "$(date "+%s")" -gt "$timeout_timestamp" ]; then
            log_error "Timeout waiting for $description to exist"
            exit 1
        else
            log_info "Waiting $interval for $description to exist..."
            sleep "$interval"
        fi
    done
}

wait_to_start_in_namespace() {
    namespace=${1:-${RHDH_NAMESPACE}}
    resource=${2:-deployment}
    name=${3:-name}
    initial_timeout=${4:-300}
    wait_timeout=${5:-300}
    rn=$resource/$name
    description=${6:-$rn}
    wait_to_exist "$namespace" "$resource" "$name" "$initial_timeout" "$description"
    $cli -n "$namespace" rollout status "$rn" --timeout="${wait_timeout}s"
    return $?
}

wait_for_crd() {
    name=${1:-name}
    initial_timeout=${2:-300}
    rn=crd/$name
    description=${3:-$rn}
    timeout_timestamp=$(python3 -c "from datetime import datetime, timedelta; t_add=int('$initial_timeout'); print(int((datetime.now() + timedelta(seconds=t_add)).timestamp()))")
    interval=10s
    while ! /bin/bash -c "$cli get $rn"; do
        if [ "$(date "+%s")" -gt "$timeout_timestamp" ]; then
            log_error "Timeout waiting for $description to exist"
            exit 1
        else
            log_info "Waiting $interval for $description to exist..."
            sleep "$interval"
        fi
    done
}

wait_to_start() {
    wait_to_start_in_namespace "$RHDH_NAMESPACE" "$@"
    return $?
}

label() {
    namespace=$1
    resource=$2
    name=$3
    label=$4
    $cli -n "$namespace" label "$resource" "$name" "$label"
}

label_n() {
    label "$RHDH_NAMESPACE" "$1" "$2" "$3"
}

annotate() {
    namespace=$1
    resource=$2
    name=$3
    annotation=$4
    $cli -n "$namespace" annotate "$resource" "$name" "$annotation"
}

annotate_n() {
    annotate "$RHDH_NAMESPACE" "$1" "$2" "$3"
}

mark_resource_for_rhdh() {
    resource=$1
    name=$2
    annotate_n "$resource" "$name" "rhdh.redhat.com/backstage-name=developer-hub"
    label_n "$resource" "$name" "rhdh.redhat.com/ext-config-sync=true"
}

export -f log_info log_warn log_error log_token log_token_info log_token_err wait_and_approve_install_plans wait_to_exist wait_to_start_in_namespace wait_for_crd wait_to_start label label_n annotate annotate_n mark_resource_for_rhdh
