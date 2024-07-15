#SHELL="/bin/bash -x"

export RHDH_OLM_INDEX_IMAGE ?= quay.io/rhdh/iib:1.2-v4.15-x86_64
export RHDH_OPERATOR_NAMESPACE ?= rhdh-operator
export RHDH_OLM_CHANNEL ?= fast
export RHDH_OLM_OPERATOR_PACKAGE ?= rhdh

.PHONY: setup
setup:
	./setup.sh

.PHONY: deploy
deploy:
	./deploy.sh

.PHONY: undeploy
undeploy:
	./undeploy.sh

.PHONY: run
run:
	./run.sh

.PHONY: clean
clean:
	./clean.sh

.PHONY: show-counts
show-counts:
	./counts.sh

