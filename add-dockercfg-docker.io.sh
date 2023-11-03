#!/bin/bash

ns="${NAMESPACE:-locust-operator}"

for s in builder default deployer locust-operator-locust-k8s-operator; do
    secret=$(kubectl get --namespace "$ns" secret -o json | jq -rc '.items[] | select(.metadata.name | startswith("'"${s}"'-dockercfg")).metadata.name')
    kubectl patch --namespace "$ns" secret $secret --type=merge -p '{"data": {".dockercfg" :"'$(kubectl get --namespace "$ns" secret $secret -o json | jq -r '.data | map_values(@base64d).".dockercfg"' | jq -rc '."https://index.docker.io/v1/".auth = "'${TOKEN}'"' | base64 -w0)'"}}'
done
