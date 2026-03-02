#!/bin/bash

set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "Usage: (DRY_RUN=true) ./generate-all.sh '<rbac_policies>' '<users:groups>'"
    echo ""
    echo "   DRY_RUN=true - do not build and push the image (default: false)"
    echo "   rbac_policies - space-separated list of RBAC policies to generate."
    echo "   users:groups - space-separated list of users:groups to generate"
    echo ""
    echo "   Examples: ./generate-all.sh 'all_groups_admin_inherited complex' '1:1 100:20 100:100 1000:250 1000:1000 1000:10000 5000:50000 10000:150000 20000:350000 30000:500000'"
    echo "             ./generate-all.sh 'all_groups_admin all_groups_admin_inherited complex' '1000:250 1000:1000'"
    echo "              DRY_RUN=true ./generate-all.sh 'all_groups_admin_inherited' '1000:250'"
    exit 1
fi

# rbac policies to generate
read -ra rbac_policies <<<"$1"

# number of users and groups to generate
read -ra users_groups <<<"$2"

# Dry run mode (do not build and push the image)
DRY_RUN=${DRY_RUN:-false}

for p in "${rbac_policies[@]}"; do
    for u_g in "${users_groups[@]}"; do
        IFS=":" read -ra tokens <<<"${u_g}"
        u=${tokens[0]}                                         # user count
        [[ "${#tokens[@]}" == 1 ]] && g="" || g="${tokens[1]}" # group count
        index="${p}-${u}u-${g}g"
        echo "Generating ${index}.ldif"
        out=seed.ldif
        BACKSTAGE_USER_COUNT=$u GROUP_COUNT=$g RBAC_POLICY=$p ./generate-seed-ldif.sh $out

        if [ "$DRY_RUN" == "false" ]; then
            image="quay.io/backstage-performance/rhdh-ldap:${index}"
            podman rmi -f "$image"
            podman build --no-cache -t "$image" .
            podman push "$image"

            rm -vf $out
        else
            mv "$out" "$index.ldif"
        fi
    done
done
