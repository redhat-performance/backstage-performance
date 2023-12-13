#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

export SCENARIO DURATION WAIT_FOR_SEARCH_INDEX PRE_LOAD_DB SCALE_WORKERS SCALE_ACTIVE_USERS_SPAWN_RATES SCALE_BS_USERS_GROUPS SCALE_CATALOG_SIZES SCALE_REPLICAS SCALE_DB_STORAGES

echo -e "\n === Running RHDH scalability test ===\n"
make test-scalability
