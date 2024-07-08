#!/bin/bash

RHDH_BASE_URL=${RHDH_BASE_URL:-localhost}

curl="curl -sSL --insecure"

token=$($curl "${RHDH_BASE_URL}/api/auth/guest/refresh" | jq -r '.backstageIdentity.token')

$curl -H "Authorization: Bearer $token" "${RHDH_BASE_URL}/api/catalog/entities?filter=kind=api" | jq -r
