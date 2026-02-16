#!/bin/bash
#
# Generates a seed.ldif file with N LDAP users for performance testing.
#
# Usage:
#   ./generate-seed-ldif.sh <num_users> [output_file]
#
# Environment variables:
#   KEYCLOAK_USER_PASS  - Password for all generated users (required)
#   GROUP_COUNT         - Number of groups to create (default: 1)
#   RBAC_POLICY         - RBAC policy type (default: all_groups_admin)
#                         Supported: all_groups_admin, all_groups_admin_inherited,
#                                    static, complex, nested_groups,
#                                    user_in_multiple_groups
#   RBAC_POLICY_SIZE    - Policy-specific size parameter (default: GROUP_COUNT)
#
# The generated LDIF matches the LDAP schema from slapd.conf and produces
# users with the same naming convention (t_<index>) and group assignment
# logic as create_resource.sh.
#
# The output is compatible with slapadd (used in Containerfile to pre-populate
# the LDAP database at image build time).

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1090,SC1091
# source "$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$SCRIPT_DIR"/../../../../test.env)"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../../common.sh"

OUTPUT_FILE="${1:-seed.ldif}"
BACKSTAGE_USER_COUNT="${BACKSTAGE_USER_COUNT:-100}"
GROUP_COUNT="${GROUP_COUNT:-100}"
KEYCLOAK_USER_PASS="${KEYCLOAK_USER_PASS:-changeme}"

# RBAC policy constants (must match create_resource.sh)
RBAC_POLICY_ALL_GROUPS_ADMIN="all_groups_admin"
RBAC_POLICY_STATIC="static"
RBAC_POLICY_COMPLEX="complex"
RBAC_POLICY_NESTED_GROUPS="nested_groups"
RBAC_POLICY_USER_IN_MULTIPLE_GROUPS="user_in_multiple_groups"
RBAC_POLICY_ALL_GROUPS_ADMIN_INHERITED="all_groups_admin_inherited"

RBAC_POLICY="${RBAC_POLICY:-$RBAC_POLICY_ALL_GROUPS_ADMIN}"
RBAC_POLICY_SIZE="${RBAC_POLICY_SIZE:-$GROUP_COUNT}"

BASE_DN="dc=test,dc=com"
USERS_OU="ou=users,${BASE_DN}"
GROUPS_OU="ou=groups,${BASE_DN}"

# Generate SSHA password hash if slappasswd is available, otherwise use plain text
generate_password_hash() {
    local password="$1"
    if command -v slappasswd &>/dev/null; then
        slappasswd -s "$password"
    else
        echo "$password"
    fi
}

# Determine which group(s) a user belongs to based on the RBAC policy.
# Mirrors the logic in create_resource.sh create_user().
#
# Args: user_index (1-based)
# Output: space-separated list of group CNs (e.g. "g1" or "g1 g2 g3")
get_user_groups() {
    local user_index="$1"
    local grp=$((user_index % GROUP_COUNT))
    [[ $grp -eq 0 ]] && grp=${GROUP_COUNT}

    case "$RBAC_POLICY" in
    "$RBAC_POLICY_ALL_GROUPS_ADMIN" | "$RBAC_POLICY_STATIC" | "$RBAC_POLICY_COMPLEX" | "$RBAC_POLICY_ALL_GROUPS_ADMIN_INHERITED")
        if [[ $GROUP_COUNT -le $BACKSTAGE_USER_COUNT ]]; then
            # More users than (or equal) groups: each user maps to one group
            echo "g${grp}"
        else
            # More groups than users: distribute groups round-robin so every
            # group gets a member.  User i gets groups i, i+USER_COUNT, ...
            local groups=""
            local g=$user_index
            while [[ $g -le $GROUP_COUNT ]]; do
                groups="${groups:+$groups }g${g}"
                g=$((g + BACKSTAGE_USER_COUNT))
            done
            echo "$groups"
        fi
        ;;
    "$RBAC_POLICY_NESTED_GROUPS")
        [[ $grp -eq 0 ]] && grp=${GROUP_COUNT}
        if [[ $grp -eq $RBAC_POLICY_SIZE ]]; then
            echo "g1"
        elif [[ $grp -gt $RBAC_POLICY_SIZE ]]; then
            echo "g${grp}"
        else
            echo "g$((RBAC_POLICY_SIZE - grp))_1"
        fi
        ;;
    "$RBAC_POLICY_USER_IN_MULTIPLE_GROUPS")
        if [[ $user_index -eq 1 ]]; then
            local groups=""
            local limit="${RBAC_POLICY_SIZE:-$GROUP_COUNT}"
            for g in $(seq 1 "${limit}"); do
                groups="${groups:+$groups }g${g}"
            done
            echo "$groups"
        else
            echo "g${grp}"
        fi
        ;;
    *)
        echo "ERROR: Unknown RBAC_POLICY: $RBAC_POLICY" >&2
        exit 1
        ;;
    esac
}

# Collect the list of all group names that need to be created.
# For nested_groups policy, this includes both top-level and nested groups.
# Output: one group name per line
get_all_group_names() {
    case "$RBAC_POLICY" in
    "$RBAC_POLICY_NESTED_GROUPS")
        local N="${RBAC_POLICY_SIZE:-$GROUP_COUNT}"
        [[ $N -gt $GROUP_COUNT ]] && N="$GROUP_COUNT"

        # g1 is always a top-level group
        echo "g1"
        # Nested chain: g1_1, g2_1, ..., g(N-2)_1
        for idx in $(seq 2 "$N"); do
            echo "g$((idx - 1))_1"
        done
        # Additional top-level groups beyond the nested chain
        if [[ $GROUP_COUNT -gt $N ]]; then
            for idx in $(seq $((N + 1)) "$GROUP_COUNT"); do
                echo "g${idx}"
            done
        fi
        ;;
    "$RBAC_POLICY_ALL_GROUPS_ADMIN_INHERITED")
        # Parent group first, then all child groups
        echo "admin_parent"
        for idx in $(seq 1 "$GROUP_COUNT"); do
            echo "g${idx}"
        done
        ;;
    *)
        # Simple flat groups: g1, g2, ..., gGROUP_COUNT
        for idx in $(seq 1 "$GROUP_COUNT"); do
            echo "g${idx}"
        done
        ;;
    esac
}

# For the nested_groups policy, determine the parent group of a given group.
# Output: parent group CN, or empty if top-level.
get_parent_group() {
    local group_name="$1"
    case "$RBAC_POLICY" in
    "$RBAC_POLICY_NESTED_GROUPS")
        # Nested chain: g1 -> g1_1 -> g2_1 -> g3_1 -> ...
        if [[ "$group_name" == "g1_1" ]]; then
            echo "g1"
        elif [[ "$group_name" =~ ^g([0-9]+)_1$ ]]; then
            local idx="${BASH_REMATCH[1]}"
            if [[ $idx -gt 1 ]]; then
                echo "g$((idx - 1))_1"
            fi
        fi
        # Top-level groups (g1, gN+1, gN+2, ...) have no parent
        ;;
    "$RBAC_POLICY_ALL_GROUPS_ADMIN_INHERITED")
        # All g1-gN groups are children of admin_parent
        if [[ "$group_name" =~ ^g[0-9]+$ ]]; then
            echo "admin_parent"
        fi
        ;;
    esac
}

echo "Generating seed.ldif with ${BACKSTAGE_USER_COUNT} users and ${GROUP_COUNT} groups..."
echo "RBAC policy: ${RBAC_POLICY} (size: ${RBAC_POLICY_SIZE})"
echo "Output file: ${OUTPUT_FILE}"

PASSWORD_HASH=$(generate_password_hash "$KEYCLOAK_USER_PASS")

# Collect all group names and build user-to-group mapping
mapfile -t ALL_GROUPS < <(get_all_group_names)

# Build associative array: group_name -> list of member user DNs
declare -A GROUP_MEMBERS

for i in $(seq 1 "${BACKSTAGE_USER_COUNT}"); do
    user_dn="uid=t_${i},${USERS_OU}"
    for grp_name in $(get_user_groups "$i"); do
        GROUP_MEMBERS["$grp_name"]+=" ${user_dn}"
    done
done

# Pre-compute parent->children mapping in a single O(n) pass so we avoid
# an O(n^2) inner loop when emitting group entries.
echo "Pre-computing parent->children mapping"
declare -A GROUP_CHILDREN
if [[ "$RBAC_POLICY" == "$RBAC_POLICY_ALL_GROUPS_ADMIN_INHERITED" ]]; then
    # All g1-gN groups are children of admin_parent; the hierarchy is known
    # upfront so we skip the per-group get_parent_group call entirely.
    for idx in $(seq 1 "$GROUP_COUNT"); do
        GROUP_CHILDREN["admin_parent"]+=" cn=g${idx},${GROUPS_OU}"
    done
elif [[ "$RBAC_POLICY" == "$RBAC_POLICY_NESTED_GROUPS" ]]; then
    for candidate in "${ALL_GROUPS[@]}"; do
        echo -n "Getting parent for $candidate: "
        candidate_parent=$(get_parent_group "$candidate")
        echo "$candidate_parent"
        if [[ -n "$candidate_parent" ]]; then
            GROUP_CHILDREN["$candidate_parent"]+=" cn=${candidate},${GROUPS_OU}"
        fi
    done
fi
echo "Generating entries"

{
    # Root entry
    cat <<EOF
dn: ${BASE_DN}
objectClass: top
objectClass: dcObject
objectClass: organization
o: RHDH Performance Test
dc: test

EOF

    # Users organizational unit
    cat <<EOF
dn: ${USERS_OU}
objectClass: top
objectClass: organizationalUnit
ou: users

EOF

    # Groups organizational unit
    cat <<EOF
dn: ${GROUPS_OU}
objectClass: top
objectClass: organizationalUnit
ou: groups

EOF

    # Generate the "guru" admin user (always present, used for auth/RBAC)
    cat <<EOF
dn: uid=guru,${USERS_OU}
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
uid: guru
cn: guru
sn: RHDH Admin
givenName: Guru
mail: guru@test.com
userPassword: ${PASSWORD_HASH}

EOF

    # Generate all user entries
    for i in $(seq 1 "${BACKSTAGE_USER_COUNT}"); do
        username="t_${i}"
        cat <<EOF
dn: uid=${username},${USERS_OU}
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
uid: ${username}
cn: ${username}
sn: tester
givenName: ${username}
mail: ${username}@test.com
userPassword: ${PASSWORD_HASH}

EOF
    done

    # Generate group entries with pre-computed members.
    # For nested_groups policy, child groups are also listed as members
    # of their parent group to model the nesting hierarchy.
    #
    # Groups with no members are skipped (groupOfNames requires at least
    # one member).  This happens when GROUP_COUNT > BACKSTAGE_USER_COUNT.
    skipped_groups=0
    for grp_name in "${ALL_GROUPS[@]}"; do
        member_buf=""

        # For nested/inherited policies, add child groups (pre-computed)
        if [[ -n "${GROUP_CHILDREN[$grp_name]:-}" ]]; then
            for child_dn in ${GROUP_CHILDREN[$grp_name]}; do
                member_buf+="member: ${child_dn}"$'\n'
            done
        fi

        # For all_groups_admin_inherited, add guru as member of admin_parent
        # if [[ "$RBAC_POLICY" == "$RBAC_POLICY_ALL_GROUPS_ADMIN_INHERITED" && "$grp_name" == "admin_parent" ]]; then
        #     member_buf+="member: uid=guru,${USERS_OU}"$'\n'
        # fi

        # Add user members (pre-computed)
        if [[ -n "${GROUP_MEMBERS[$grp_name]:-}" ]]; then
            for member_dn in ${GROUP_MEMBERS[$grp_name]}; do
                member_buf+="member: ${member_dn}"$'\n'
            done
        fi

        # groupOfNames requires at least one member; skip empty groups
        if [[ -z "$member_buf" ]]; then
            skipped_groups=$((skipped_groups + 1))
            continue
        fi

        printf 'dn: cn=%s,%s\nobjectClass: top\nobjectClass: groupOfNames\ncn: %s\n%s\n' \
            "$grp_name" "$GROUPS_OU" "$grp_name" "$member_buf"
    done
    if [[ $skipped_groups -gt 0 ]]; then
        echo "WARNING: Skipped ${skipped_groups} empty group(s) (GROUP_COUNT > BACKSTAGE_USER_COUNT)." >&2
    fi
} >"${OUTPUT_FILE}"

emitted_groups=$((${#ALL_GROUPS[@]} - skipped_groups))
echo "Generated ${OUTPUT_FILE} with ${BACKSTAGE_USER_COUNT} users and ${emitted_groups} groups (${skipped_groups} empty group(s) skipped out of ${#ALL_GROUPS[@]})."
echo "Base DN: ${BASE_DN}"
echo "User DN pattern: uid=t_<index>,${USERS_OU}"
echo "Group DN pattern: cn=g<index>,${GROUPS_OU}"
echo "Groups: ${ALL_GROUPS[*]}"
