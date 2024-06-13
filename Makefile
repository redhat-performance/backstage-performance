# Override test environment variables
ifneq (,$(wildcard test.env))
	include test.env
endif

# Scenario to run. It correlates with the locust file at scenarios/<SCENARIO>.py
export SCENARIO ?= baseline-test

# Used to set --host option of locust CLI (base URL to load test). See https://docs.locust.io/en/stable/configuration.html#command-line-options for details
export HOST ?= http://localhost

export KEYCLOAK_USER_PASS ?= $(shell mktemp -u XXXXXXXXXX)
# Used to set --users option of locust CLI (Peak number of concurrent Locust users.). See https://docs.locust.io/en/stable/configuration.html#command-line-options for details
export USERS ?= 100

# Number of locust worker pods
export WORKERS ?= 5

# Used to set --run-time option of locust CLI (Stop after the specified amount of time, e.g. (300s, 20m, 3h, 1h30m, etc.). See https://docs.locust.io/en/stable/configuration.html#command-line-options for details
export DURATION ?= 1m

# Used to set --spawn-rate option of locust CLI (Rate to spawn users at (users per second)).  See https://docs.locust.io/en/stable/configuration.html#command-line-options for details
export SPAWN_RATE ?= 20

# RHDH image to deploy. Uncomment and set to override RHDH image to deploy and test.
export RHDH_IMAGE_REGISTRY ?=
export RHDH_IMAGE_REPO ?=
export RHDH_IMAGE_TAG ?=

# RHDH Helm chart to deploy
export RHDH_NAMESPACE ?= rhdh-performance
export RHDH_HELM_REPO ?= https://raw.githubusercontent.com/rhdh-bot/openshift-helm-charts/rhdh-1.1-rhel-9/installation
export RHDH_HELM_CHART ?= redhat-developer-hub
export RHDH_HELM_CHART_VERSION ?=
export RHDH_HELM_RELEASE_NAME ?= rhdh

# RHDH OLM subscription to deploy
export RHDH_OLM_INDEX_IMAGE ?= registry.redhat.io/redhat/redhat-operator-index:v$(shell oc version -o json | jq -r '.openshiftVersion' | sed -r -e "s,([0-9]+\.[0-9]+)\..+,\1,")
export RHDH_OLM_CHANNEL ?= fast-1.1

# RHDH horizontal scaling
export RHDH_DEPLOYMENT_REPLICAS ?= 1
export RHDH_DB_REPLICAS ?= 1
export RHDH_DB_STORAGE ?= 1Gi
export RHDH_RESOURCES_CPU_REQUESTS ?=
export RHDH_RESOURCES_CPU_LIMITS ?=
export RHDH_RESOURCES_MEMORY_REQUESTS ?=
export RHDH_RESOURCES_MEMORY_LIMITS ?=
export RHDH_KEYCLOAK_REPLICAS ?= 1
export LOCUST_EXTRA_CMD ?=
export AUTH_PROVIDER ?=

# RHDH install method - one of 'helm' or 'olm'
export RHDH_INSTALL_METHOD ?= helm

# python's venv base dir relative to the root of the repository
PYTHON_VENV=.venv

# Local directory to store temporary files
export TMP_DIR=$(shell readlink -m .tmp)

# Local directory to store artifacts
export ARTIFACT_DIR ?= $(shell readlink -m .artifacts)

# Name of the namespace to install locust operator as well as to run Pods of master and workers.
LOCUST_NAMESPACE=locust-operator

# Helm repository name to install locust operator from
LOCUST_OPERATOR_REPO=locust-k8s-operator

# Helm chart of locust operator
LOCUST_OPERATOR=locust-operator

.DEFAULT_GOAL := help

##	=== Setup Environment ===

## Setup python's virtual environment
.PHONY: setup-venv
setup-venv:
	python3 -m venv $(PYTHON_VENV)
	$(PYTHON_VENV)/bin/python3 -m pip install --upgrade pip
	$(PYTHON_VENV)/bin/python3 -m pip install -r requirements.txt

.PHONY: namespace
namespace:
	@kubectl create namespace $(LOCUST_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -

##	=== Red Hat Developer Hub (RHDH)

## Deploy RHDH with Helm
.PHONY: deploy-rhdh-helm
deploy-rhdh-helm: $(TMP_DIR)
	date --utc -Ins>$(TMP_DIR)/deploy-before
	cd ./ci-scripts/rhdh-setup/; ./deploy.sh -i "$(AUTH_PROVIDER)"
	date --utc -Ins>$(TMP_DIR)/deploy-after

## Create users, groups and objects such as components and APIs in RHDH
.PHONY: populate-rhdh
populate-rhdh: $(TMP_DIR)
	date --utc -Ins>$(TMP_DIR)/populate-before
ifeq ($(RHDH_INSTALL_METHOD),helm)
	cd ./ci-scripts/rhdh-setup/; ./deploy.sh -c "$(AUTH_PROVIDER)"
else ifeq ($(RHDH_INSTALL_METHOD),olm)
	cd ./ci-scripts/rhdh-setup/; ./deploy.sh -o -c "$(AUTH_PROVIDER)"
endif
	date --utc -Ins>$(TMP_DIR)/populate-after

## Undeploy RHDH with Helm
.PHONY: undeploy-rhdh-helm
undeploy-rhdh-helm:
	cd ./ci-scripts/rhdh-setup/; ./deploy.sh -d

## Create temp directory
.PHONY: $(TMP_DIR)
$(TMP_DIR):
	mkdir -p $(TMP_DIR)

## Create artifacts directory
.PHONY: $(ARTIFACT_DIR)
$(ARTIFACT_DIR):
	mkdir -p $(ARTIFACT_DIR)

## Deploy RHDH with OLM
.PHONY: deploy-rhdh-olm
deploy-rhdh-olm: $(TMP_DIR)
	date --utc -Ins>$(TMP_DIR)/deploy-before
	cd ./ci-scripts/rhdh-setup; ./deploy.sh -o -i "$(AUTH_PROVIDER)"
	date --utc -Ins>$(TMP_DIR)/deploy-after

## Undeploy RHDH with OLM
.PHONY: undeploy-rhdh-olm
undeploy-rhdh-olm:
	cd ./ci-scripts/rhdh-setup; ./deploy.sh -o -d

##	=== Locust Operator ===

## Deploy and install locust operator helm chart
.PHONY: deploy-locust
deploy-locust: namespace
	@if ! helm repo list --namespace $(LOCUST_NAMESPACE) | grep -q "$(LOCUST_OPERATOR_REPO)"; then \
		helm repo add $(LOCUST_OPERATOR_REPO) https://abdelrhmanhamouda.github.io/locust-k8s-operator/ --namespace $(LOCUST_NAMESPACE); \
	else \
		echo "Helm repo \"$(LOCUST_OPERATOR_REPO)\" already exists"; \
	fi
	@if ! helm list --namespace $(LOCUST_NAMESPACE) | grep -q "$(LOCUST_OPERATOR)"; then \
		helm install $(LOCUST_OPERATOR) locust-k8s-operator/locust-k8s-operator --namespace $(LOCUST_NAMESPACE) --values ./config/locust-k8s-operator.values.yaml; \
	else \
		echo "Helm release \"$(LOCUST_OPERATOR)\" already exists"; \
	fi

## Uninstall locust operator helm chart
.PHONY: undeploy-locust
undeploy-locust: clean
	@kubectl delete namespace $(LOCUST_NAMESPACE) --wait
	@helm repo remove $(LOCUST_OPERATOR_REPO)

##	=== Testing ===

## Remove test related resources from cluster
## Run `make clean SCENARIO=...` to clean a specific scenario from cluster
.PHONY: clean
clean:
	kubectl delete --namespace $(LOCUST_NAMESPACE) cm locust.$(SCENARIO) --ignore-not-found --wait
	kubectl delete --namespace $(LOCUST_NAMESPACE) locusttests.locust.io $(SCENARIO).test --ignore-not-found --wait || true

## Deploy and run the locust test
## Run `make test SCENARIO=...` to run a specific scenario
.PHONY: test
test: $(TMP_DIR) $(ARTIFACT_DIR)
	echo $(SCENARIO)>$(TMP_DIR)/benchmark-scenario
ifneq ($(shell test '$(AUTH_PROVIDER)' == 'keycloak' && echo 1 || echo 0),0)
	$(eval key_pass := $(shell oc -n  rhdh-performance  get secret perf-test-secrets -o template --template='{{.data.keycloak_user_pass}}' | base64 -d))
	$(eval key_host := $(shell oc  -n  rhdh-performance  get routes/keycloak -o template  --template='{{.spec.host}}' ))
	$(eval LOCUST_EXTRA_CMD := --keycloak-host $(key_host) --keycloak-password $(key_pass)  )
ifneq ($(shell test $(USERS) -gt $(WORKERS) && echo 1 || echo 0),0)
	@echo "users greater than  workers "
else
	$(eval WORKERS := $(USERS))
endif
else
	@echo "no changes"
endif
	cat locust-test-template.yaml | envsubst | kubectl apply --namespace $(LOCUST_NAMESPACE) -f -
	kubectl create --namespace $(LOCUST_NAMESPACE) configmap locust.$(SCENARIO) --from-file scenarios/$(SCENARIO).py --dry-run=client -o yaml | kubectl apply --namespace $(LOCUST_NAMESPACE) -f -
	date --utc -Ins>$(TMP_DIR)/benchmark-before
	timeout=$$(date -d "480 seconds" "+%s"); while [ -z "$$(kubectl get --namespace $(LOCUST_NAMESPACE) pod -l performance-test-pod-name=$(SCENARIO)-test-master -o name)" ]; do if [ "$$(date "+%s")" -gt "$$timeout" ]; then echo "ERROR: Timeout waiting for locust master pod to start"; exit 1; else echo "Waiting for locust master pod to start..."; sleep 5s; fi; done
	kubectl wait --namespace $(LOCUST_NAMESPACE) --for=condition=Ready=true $$(kubectl get --namespace $(LOCUST_NAMESPACE) pod -l performance-test-pod-name=$(SCENARIO)-test-master -o name)
	@echo "Getting locust master log:"
	kubectl logs --namespace $(LOCUST_NAMESPACE) -f -l performance-test-pod-name=$(SCENARIO)-test-master | tee load-test.log
	date --utc -Ins>$(TMP_DIR)/benchmark-after
	@echo "All done!!!"

## Run the scalability test
## Run `make test-scalability SCENARIO=...` to run a specific scenario
.PHONY: test-scalability
test-scalability:
	cd ./ci-scripts/scalability; ./test-scalability.sh

## Run shellcheck on all of the shell scripts
.PHONY: shellcheck
shellcheck:
	if [ ! -f ./shellcheck ]; then curl -sSL -o shellcheck.tar.xz https://github.com/koalaman/shellcheck/releases/download/stable/shellcheck-stable.linux.x86_64.tar.xz; tar -xvf shellcheck.tar.xz --wildcards --strip-components=1 shellcheck-stable/shellcheck; rm -rvf shellcheck.tar.xz; fi
	./shellcheck $$(find -name '*.sh')

## Run all linters
.PHONY: lint
lint: shellcheck
	shellcheck $$(find -name '*.sh')

##	=== CI ===

## Run the load test in CI end to end
.PHONY: ci-run
ci-run: setup-venv deploy-locust test

## Deploy and populate RHDH in CI end to end
.PHONY: ci-deploy
ci-deploy: namespace
ifeq ($(RHDH_INSTALL_METHOD),helm)
ci-deploy: deploy-rhdh-helm
else ifeq ($(RHDH_INSTALL_METHOD),olm)
ci-deploy: deploy-rhdh-olm
endif


##	=== Maintanence ===

## Make the locust images in quay.io up to date with docker.io
## Requires write permissions to quay.io/backstage-performance organization or individual repos
.PHONY: update-locust-images
update-locust-images:
	skopeo copy --src-no-creds docker://docker.io/locustio/locust:latest docker://quay.io/backstage-performance/locust:latest
	skopeo copy --src-no-creds docker://docker.io/containersol/locust_exporter:latest docker://quay.io/backstage-performance/locust_exporter:latest
	skopeo copy --src-no-creds docker://docker.io/lotest/locust-k8s-operator:latest docker://quay.io/backstage-performance/locust-k8s-operator:latest

## Clean local resources
.PHONY: clean-local
clean-local:
	rm -rvf *.log shellcheck $(TMP_DIR) $(ARTIFACT_DIR)

## Clean all
.PHONY: clean-all
clean-all: namespace clean clean-local
ifeq ($(RHDH_INSTALL_METHOD),helm)
clean-all: undeploy-rhdh-helm
else ifeq ($(RHDH_INSTALL_METHOD),olm)
clean-all: undeploy-rhdh-olm
endif

##	=== Help ===

## Print help message for all Makefile targets
## Run `make` or `make help` to see the help
.PHONY: help
help: ## Credit: https://gist.github.com/prwhite/8168133#gistcomment-2749866

	@printf "Usage:\n  make <target>\n\n";

	@awk '{ \
			if ($$0 ~ /^.PHONY: [a-zA-Z\-_0-9]+$$/) { \
				helpCommand = substr($$0, index($$0, ":") + 2); \
				if (helpMessage) { \
					printf "\033[36m%-20s\033[0m %s\n", \
						helpCommand, helpMessage; \
					helpMessage = ""; \
				} \
			} else if ($$0 ~ /^[a-zA-Z\-_0-9.]+:/) { \
				helpCommand = substr($$0, 0, index($$0, ":")); \
				if (helpMessage) { \
					printf "\033[36m%-20s\033[0m %s\n", \
						helpCommand, helpMessage; \
					helpMessage = ""; \
				} \
			} else if ($$0 ~ /^##/) { \
				if (helpMessage) { \
					helpMessage = helpMessage"\n                     "substr($$0, 3); \
				} else { \
					helpMessage = substr($$0, 3); \
				} \
			} else { \
				if (helpMessage) { \
					print "\n                     "helpMessage"\n" \
				} \
				helpMessage = ""; \
			} \
		}' \
		$(MAKEFILE_LIST)
