# Backstage performance benchmarking tool

## Prerequisites

Ensure your system has all the CLI and tools as shown in the [OpenShift CI runner Containerfile](https://github.com/openshift/release/blob/master/ci-operator/config/redhat-performance/backstage-performance/redhat-performance-backstage-performance-main.yaml#L7) or compatible versions.

## How to...
Everything is driven by [`Makefile`](./Makefile). For the details how to do various things see the [`Makefile`](./Makefile)'s inline comments or run `make help`.


## Setup the environment

The RHDH performance testing framework is optimized to run in OpenShift CI environment where secrets are provided to the environment via files stored under `/usr/local/ci-secrets/backstage-performance` directory. (See [OpenShift CI Docs](https://docs.ci.openshift.org/docs/how-tos/adding-a-new-secret-to-ci/))

The framework assumes the following credentials files under the `/usr/local/ci-secrets/backstage-performance` directory with secrets exists and maps them to the following environment variables:

| Credential file | Mapped environment Variable | Description | Example |
| :--- | ---- | ---- | ---- |
| github.accounts   | Used to mitigate Github rate limits attemtps. | Comma separated list of colon separated tuples of Github username and token | `gh_user1:ghp_token1,gh_user2:ghp_token2`. |
| github.org | GITHUB_ORG | Name of the Github organization. Used to clean the test repos branches created for RHDH Catalog locations.| `example-org` |
| github.repo | GITHUB_REPO | URL of the Github Repo used for creating RHDH catalog locations. |`https://github.com/example-org/rhdh-perf-testing-repo.git` |
| github.user | GITHUB_USER | Github username with permissions to the above github repo | `gh_user1` |
| github.token | GITHUB_TOKEN | Personal access token (classic) of the above Github user with the `delete_repo, repo, workflow` permissions | `ghp_token1` |
| quay.token | QUAY_TOKEN | A pull secret for getting RHDH (and other) images from Quay.io (and other registries). A base64 encoded docker.json config file | - |

Make sure to create the `/usr/local/ci-secrets/backstage-performance` directory in your system where you intend to run the RHDH performance framework and create and fill the above files with the respective credentials.

Additionally, make sure you have an OpenShift cluster with the admin permissions to it and you have exported the appropriate `KUBECONFIG` environmental variable for the performance framework to be able to access it.

# Running the RHDH performance tests

The framework operations are divided into 3 phases:
* Setup
* Test
* Collect results

## Testing RHDH performance
The RHDH is deployed on the OpenShift cluster provisioned on AWS along with the load generating framework simulating concurrent active users interacting with RHDH from multiple places.

RHDH is installed using Helm chart (or OLM operator) with KeyCloak used both as identity provider and OAuth2 server. Both RHDH and KeyCloak have their own PostgreSQL DB all deployed on OpenShift in a single namespace (`rhdh-performance` by default). RHDH has an additional container with `oauth2-proxy` to make the API secure. The test users and groups are created in KeyCloak and the entities are added to the RHDH Catalog during installation.

The load generating part is driven by the [Locust.io Operator](https://abdelrhmanhamouda.github.io/locust-k8s-operator/getting_started/) deployed in the `locust-operator` namespace by default.

The central configuration to control the setup and the performance test itself is the `test.env` file where all the configuration is provided.

To install RHDH and populate the DB with test users, groups and catalog entities:

1. Create `.setenv.local` file with the following content:
```bash
#!/bin/bash

export GITHUB_TOKEN
export GITHUB_USER
export GITHUB_REPO
export QUAY_TOKEN

GITHUB_TOKEN="$(cat /usr/local/ci-secrets/backstage-performance/github.token)"
GITHUB_USER="$(cat /usr/local/ci-secrets/backstage-performance/github.user)"
GITHUB_REPO="$(cat /usr/local/ci-secrets/backstage-performance/github.repo)"
QUAY_TOKEN="$(cat /usr/local/ci-secrets/backstage-performance/quay.token)"
```

2. Uncomment and set at least the following variables in the `test.env`
```bash
# Test phase
export SCENARIO=mvp
export USERS=10
export WORKERS=100
export DURATION=10m
export SPAWN_RATE=20
export WAIT_FOR_SEARCH_INDEX=false

# Setup phase
export PRE_LOAD_DB=true
export BACKSTAGE_USER_COUNT=100
export GROUP_COUNT=25
export API_COUNT=250
export COMPONENT_COUNT=250
export KEYCLOAK_USER_PASS=changeme
export AUTH_PROVIDER=keycloak

export RHDH_INSTALL_METHOD=helm
export RHDH_HELM_CHART_VERSION=1.8-164-CI

export RHDH_DEPLOYMENT_REPLICAS=1
export RHDH_DB_REPLICAS=1
export RHDH_DB_STORAGE=2Gi
export RHDH_KEYCLOAK_REPLICAS=1

export ENABLE_RBAC=true
export ENABLE_ORCHESTRATOR=true

export RHDH_LOG_LEVEL=debug
```

### [Setup phase] To setup RHDH and populate DB run the following command:
```bash
source .setenv.local;
make clean-all |& tee clean.log;
./ci-scripts/setup.sh |& tee setup.log;
```

The intermediate files useful for debugging are stored under `.tmp` directory.

### [Test phase] To execute a single performance test run the following the command:
```bash
./ci-scripts/test.sh |& tee test.log;
```

### [Collect Results phase] To collect the resutls and metrics run the following command:
```bash
/ci-scripts/collect-results.sh |& tee collect-results.log
```
The artifacts are collected and stored in a directory specified by the `ARTIFACT_DIR` environment variable (`.artifacts` being the default)
