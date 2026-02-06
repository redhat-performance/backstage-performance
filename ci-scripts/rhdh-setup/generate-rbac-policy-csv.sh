#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

export WORKDIR

WORKDIR=${WORKDIR:-$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' .)}
mkdir -p "$WORKDIR"

export RBAC_POLICY_ALL_GROUPS_ADMIN="all_groups_admin" #default
export RBAC_POLICY_STATIC="static"
export RBAC_POLICY_USER_IN_MULTIPLE_GROUPS="user_in_multiple_groups"
export RBAC_POLICY_NESTED_GROUPS="nested_groups"
export RBAC_POLICY_COMPLEX="complex"

export INSTALL_METHOD=${INSTALL_METHOD:-helm}
export ENABLE_ORCHESTRATOR=${ENABLE_ORCHESTRATOR:-false}
export GROUP_COUNT=${GROUP_COUNT:-10}
export BACKSTAGE_USER_COUNT=${BACKSTAGE_USER_COUNT:-10}
export RBAC_POLICY_SIZE=${RBAC_POLICY_SIZE:-10}
export RBAC_POLICY=${RBAC_POLICY:-all_groups_admin}
export OUTPUT_PATH=${OUTPUT_PATH:-/rbac-data/}

mkdir -p "$OUTPUT_PATH"

# Generate RBAC policy CSV file and upload to GitHub
# Sets RBAC_POLICY_FILE_URL to the raw GitHub URL
create_rbac_policy_csv() {
  policy="${1:-$RBAC_POLICY_ALL_GROUPS_ADMIN}"
  log_info "Generating RBAC policy CSV file for policy: $policy"

  csv_file="$OUTPUT_PATH/rbac-policy.csv"

  # Start with base policy rules
  cat >"$csv_file" <<'EOF'
p, role:default/a, kubernetes.proxy, use, allow
p, role:default/a, catalog-entity, read, allow
p, role:default/a, catalog.entity.create, create, allow
p, role:default/a, catalog.location.create, create, allow
p, role:default/a, catalog.location.read, read, allow
g, user:default/guru, role:default/a
g, user:development/guest, role:default/a
EOF

  # Add complex policy rules if needed
  if [[ $policy == "$RBAC_POLICY_COMPLEX" ]]; then
    sed 's/^    //' "$WORKDIR/complex-rbac-config.csv" >>"$csv_file"
  fi

  # Add orchestrator rules if needed
  if [[ "$INSTALL_METHOD" == "helm" ]] && ${ENABLE_ORCHESTRATOR:-false}; then
    sed 's/^    //' "$WORKDIR/orchestrator-rbac-patch.csv" >>"$csv_file"
    if [[ $policy == "$RBAC_POLICY_COMPLEX" ]]; then
      sed 's/^    //' "$WORKDIR/complex-orchestrator-rbac-patch.csv" >>"$csv_file"
    fi
  fi

  # Add group/user-specific policy rules
  case $policy in
  "$RBAC_POLICY_ALL_GROUPS_ADMIN")
    for i in $(seq 1 "$GROUP_COUNT"); do
      echo "g, group:default/g${i}, role:default/a" >>"$csv_file"
    done
    ;;
  "$RBAC_POLICY_USER_IN_MULTIPLE_GROUPS")
    group_condition="group in ["
    for g in $(seq 1 "${RBAC_POLICY_SIZE:-$GROUP_COUNT}"); do
      if [ "$g" -gt 1 ]; then
        group_condition="$group_condition,"
      fi
      group_condition="$group_condition'g$g'"
    done
    group_condition="$group_condition]"
    for u in $(seq 1 "$BACKSTAGE_USER_COUNT"); do
      if [ "$u" -eq 1 ]; then
        echo "g, user:default/t${u}, role:default/a, $group_condition" >>"$csv_file"
      else
        echo "g, user:default/t${u}, role:default/a" >>"$csv_file"
      fi
    done
    ;;
  "$RBAC_POLICY_STATIC")
    for i in $(seq 1 "${RBAC_POLICY_SIZE:-$GROUP_COUNT}"); do
      echo "g, group:default/g${i}, role:default/a" >>"$csv_file"
    done
    ;;
  "$RBAC_POLICY_NESTED_GROUPS")
    N="${RBAC_POLICY_SIZE:-$GROUP_COUNT}"
    [ "$N" -gt "$GROUP_COUNT" ] && N="$GROUP_COUNT"

    for i in $(seq 1 "$N"); do
      if [ "$i" -eq 1 ] || [ "$i" -gt "$RBAC_POLICY_SIZE" ]; then
        echo "g, group:default/g1, role:default/a" >>"$csv_file"
      else
        echo "g, group:default/g$((i - 1))_1, role:default/a" >>"$csv_file"
      fi
    done
    ;;
  "$RBAC_POLICY_COMPLEX")
    ROLES=("platform_admin" "engineering_lead" "senior_engineer" "backend_engineer" "frontend_engineer" "product_manager" "QA_engineer" "external_contractor" "compliance_security" "on_call_team")
    ROLES_LEN=${#ROLES[@]}
    for i in $(seq 1 "$GROUP_COUNT"); do
      echo "g, group:default/g${i}, role:default/${ROLES[$(((i - 1) % ROLES_LEN))]}" >>"$csv_file"
    done
    ;;
  *)
    log_error "Invalid RBAC policy: ${policy}"
    return 1
    ;;
  esac

  log_info "RBAC policy CSV file generated: $csv_file"

  cat "$csv_file"
}

create_rbac_policy_csv "$RBAC_POLICY"
