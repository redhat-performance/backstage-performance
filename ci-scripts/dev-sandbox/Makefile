#SHELL="/bin/bash -x"

export RHDH_OLM_INDEX_IMAGE ?= registry.redhat.io/redhat/redhat-operator-index:v4.15
export RHDH_OPERATOR_NAMESPACE ?= rhdh-operator
export RHDH_OLM_CHANNEL ?= fast
export RHDH_OLM_OPERATOR_PACKAGE ?= rhdh
export RHDH_OLM_WATCH_EXT_CONF ?= true

export RHDH_WORKLOADS_TEMPLATE_NAME ?= default
export NUMBER_OF_RUNS ?= 10
export NUMBER_OF_USERS_PER_RUN ?= 2000
export NUMBER_OF_USERS_WITH_WORKLOADS_PER_RUN ?= 2000

export ARTIFACT_DIR ?=

.PHONY: setup-toolchain-e2e
setup-toolchain-e2e:
	./setup-toolchain-e2e.sh

.PHONY: deploy
deploy:
	./deploy.sh

.PHONY: undeploy
undeploy:
	./undeploy.sh

.PHONY: run
run:
	./run.sh "$(NUMBER_OF_RUNS)" "$(NUMBER_OF_USERS_PER_RUN)" "$(NUMBER_OF_USERS_WITH_WORKLOADS_PER_RUN)"

.PHONY: collect-results
collect-results:
	./collect-results.sh

.PHONY: clean
clean:
	./clean.sh

.PHONY: show-counts
show-counts:
	./counts.sh

.PHONY: ci-setup
ci-setup: setup-toolchain-e2e deploy

.PHONY: ci-test
ci-test: run

.PHONY: ci-collect-results
ci-collect-results: collect-results

.PHONY: ci-clean
ci-clean: undeploy clean
