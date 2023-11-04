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
		helm install $(LOCUST_OPERATOR) locust-k8s-operator/locust-k8s-operator --namespace $(LOCUST_NAMESPACE); \
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
	kubectl delete --namespace $(LOCUST_NAMESPACE) locusttest $(SCENARIO).test --ignore-not-found --wait

## Deploy and run the locust test
## Run `make test SCENARIO=...` to run a specific scenario
.PHONY: test
test:
	cat locust-test-template.yaml | envsubst | kubectl apply --namespace $(LOCUST_NAMESPACE) -f -
	kubectl create --namespace $(LOCUST_NAMESPACE) configmap locust.$(SCENARIO) --from-file scenarios/$(SCENARIO).py --dry-run=client -o yaml | kubectl apply --namespace $(LOCUST_NAMESPACE) -f -
	kubectl wait --namespace $(LOCUST_NAMESPACE) --for=condition=Ready=true $$(kubectl get --namespace $(LOCUST_NAMESPACE) pod -l performance-test-pod-name=$(SCENARIO)-test-master -o name)
	kubectl logs --namespace $(LOCUST_NAMESPACE) -f -l performance-test-pod-name=$(SCENARIO)-test-master

##	=== CI ===

## Run the load test in CI end to end
.PHONY: ci-run
ci-run: setup-venv deploy-locust add-dockerio test

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
