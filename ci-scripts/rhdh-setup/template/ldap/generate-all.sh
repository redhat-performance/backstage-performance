#!/bin/bash

set -euo pipefail

read -ra users_groups <<<"1:1 100:100 1000:10000 5000:50000 10000:150000 20000:350000 30000:500000"

# Dry run mode (do not build and push the image)
DRY_RUN=${DRY_RUN:-false}

for p in all_groups_admin_inherited complex; do
    for u_g in "${users_groups[@]}"; do
        IFS=":" read -ra tokens <<<"${u_g}"
        u=${tokens[0]}                                         # user count
        [[ "${#tokens[@]}" == 1 ]] && g="" || g="${tokens[1]}" # group count
        echo "Generating $p-${u}u-${g}g.ldif"
        out=seed.ldif
        set -x
        BACKSTAGE_USER_COUNT=$u GROUP_COUNT=$g RBAC_POLICY=$p ./generate-seed-ldif.sh $out

        if [ "$DRY_RUN" == "false" ]; then
            image="quay.io/backstage-performance/rhdh-ldap:$p-${u}u-${g}g"
            podman rmi -f "$image"
            podman build --no-cache -t "$image" .
            podman push "$image"
        fi

        rm -vf $out
    done
done
