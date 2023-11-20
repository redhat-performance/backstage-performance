# Scenario to run. It correlates with the locust file at scenarios/<SCENARIO>.py
export SCENARIO ?= baseline-test

# Used to set --host option of locust CLI (base URL to load test). See https://docs.locust.io/en/stable/configuration.html#command-line-options for details
export HOST ?= http://localhost

# Used to set --users option of locust CLI (Peak number of concurrent Locust users.). See https://docs.locust.io/en/stable/configuration.html#command-line-options for details
export USERS ?= 100

# Number of locust worker pods
export WORKERS ?= 5

# Used to set --run-time option of locust CLI (Stop after the specified amount of time, e.g. (300s, 20m, 3h, 1h30m, etc.). See https://docs.locust.io/en/stable/configuration.html#command-line-options for details
export DURATION ?= 1m

# Used to set --spawn-rate option of locust CLI (Rate to spawn users at (users per second)).  See https://docs.locust.io/en/stable/configuration.html#command-line-options for details
export SPAWN_RATE ?= 20

# RHDH image to deploy
export RHDH_IMAGE_REGISTRY ?= quay.io
export RHDH_IMAGE_REPO ?= rhdh/rhdh-hub-rhel9
export RHDH_IMAGE_TAG ?= 1.0-162

# RHDH Helm chart to deploy
export RHDH_NAMESPACE ?= rhdh-performance
export RHDH_HELM_REPO ?= https://gist.githubusercontent.com/nickboldt/a8483eb244f9c4286798e85accaa70af/raw/
export RHDH_HELM_CHART ?= developer-hub
export RHDH_HELM_RELEASE_NAME ?= rhdh

# RHDH horizontal scaling
export RHDH_DEPLOYMENT_REPLICAS ?= 1
export RHDH_DB_REPLICAS ?= 1
export RHDH_KEYCLOAK_REPLICAS ?= 1

# python's venv base dir relative to the root of the repository
PYTHON_VENV=.venv

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

## Deploy RHDH
.PHONY: deploy-rhdh
deploy-rhdh:
	./ci-scripts/setup.sh

## Undeploy RHDH
.PHONY: undeploy-rhdh
undeploy-rhdh:
	./ci-scripts/rhdh-setup/deploy.sh -d

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

## Add docker.io token to default-dockercfg-* Secret to avoid pull rate limits from docker.io
## Run `make add-dockerio DOCKERIO_TOKEN=...`
.PHONY: add-dockerio
add-dockerio: namespace
	@TOKEN=$(DOCKERIO_TOKEN) NAMESPACE=$(LOCUST_NAMESPACE) ./add-dockercfg-docker.io.sh

##	=== Testing ===

## Remove test related resources from cluster
## Run `make clean SCENARIO=...` to clean a specific scenario
.PHONY: clean
clean:
	kubectl delete --namespace $(LOCUST_NAMESPACE) cm locust.$(SCENARIO) --ignore-not-found --wait
	kubectl delete --namespace $(LOCUST_NAMESPACE) locusttests.locust.io $(SCENARIO).test --ignore-not-found --wait || true

## Deploy and run the locust test
## Run `make test SCENARIO=...` to run a specific scenario
.PHONY: test
test:
	echo $(SCENARIO)>benchmark-scenario
	cat locust-test-template.yaml | envsubst | kubectl apply --namespace $(LOCUST_NAMESPACE) -f -
	kubectl create --namespace $(LOCUST_NAMESPACE) configmap locust.$(SCENARIO) --from-file scenarios/$(SCENARIO).py --dry-run=client -o yaml | kubectl apply --namespace $(LOCUST_NAMESPACE) -f -
	date --utc -Ins>benchmark-before
	timeout=$$(date -d "30 seconds" "+%s"); while [ -z "$$(kubectl get --namespace $(LOCUST_NAMESPACE) pod -l performance-test-pod-name=$(SCENARIO)-test-master -o name)" ]; do if [ "$$(date "+%s")" -gt "$$timeout" ]; then echo "ERROR: Timeout waiting for locust master pod to start"; exit 1; else echo "Waiting for locust master pod to start..."; sleep 5s; fi; done
	kubectl wait --namespace $(LOCUST_NAMESPACE) --for=condition=Ready=true $$(kubectl get --namespace $(LOCUST_NAMESPACE) pod -l performance-test-pod-name=$(SCENARIO)-test-master -o name)
	@echo "Getting locust master log:"
	kubectl logs --namespace $(LOCUST_NAMESPACE) -f -l performance-test-pod-name=$(SCENARIO)-test-master | tee load-test.log
	date --utc -Ins>benchmark-after
	@echo "All done!!!"

##	=== CI ===

## Run the load test in CI end to end
.PHONY: ci-run
ci-run: setup-venv deploy-locust add-dockerio test

##	=== Maintanence ===

## Make the locust images in quay.io up to date with docker.io
## Requires write permissions to quay.io/backstage-performance organization or individual repos
.PHONY: update-locust-images
update-locust-images:
	skopeo copy --src-no-creds docker://docker.io/locustio/locust:latest docker://quay.io/backstage-performance/locust:latest
	skopeo copy --src-no-creds docker://docker.io/containersol/locust_exporter:latest docker://quay.io/backstage-performance/locust_exporter:latest
	skopeo copy --src-no-creds docker://docker.io/lotest/locust-k8s-operator:latest docker://quay.io/backstage-performance/locust-k8s-operator:latest

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
