# Copyright 2023 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

PROJECT_ID ?= $(shell gcloud config get-value project 2>&1 | head -n 1)
BOSKOS_RESOURCE_TYPE ?= gke-internal-project
RUN_IN_PROW ?= false
PKG_DIR ?= src/github.com/GoogleCloudPlatform/gke-networking-recipes
NETWORK_NAME ?= gke-net-recipes-test
SUBNET_NAME ?= gke-net-recipes-test
CLUSTER_NAME ?= gke-net-recipes-test
ZONE ?= us-west1-a
NUM_NODES ?= 3
TEST_TO_RUN ?= .*
JOB_NAME ?= gke-networking-recipe-e2e
DELETE_CLUSTER ?= false
DESTROY_SANDBOXES ?= true

all: bin/recipes-test

bin/recipes-test:
	mkdir bin/
	go test -c -o $@ ./test

.PHONY: test
test: bin/recipes-test
	bin/recipes-test \
		--run-in-prow=$(RUN_IN_PROW) \
		--boskos-resource-type=$(BOSKOS_RESOURCE_TYPE) \
		--pkg-dir=$(PKG_DIR) \
		--test-project-id=$(PROJECT_ID) \
		--network-name=$(NETWORK_NAME) \
		--subnet-name=$(SUBNET_NAME) \
		--cluster-name=$(CLUSTER_NAME) \
		--zone=$(ZONE) \
		--num-nodes=$(NUM_NODES) \
		--delete-cluster=$(DELETE_CLUSTER) \
		--destroySandboxes=$(DESTROY_SANDBOXES) \
		-test.run=$(TEST_TO_RUN) \

.PHONY: cleanenv
cleanenv:
	test/cleanup.sh -n $(NETWORK_NAME) -s $(SUBNET_NAME) -c $(CLUSTER_NAME) -z $(ZONE)

.PHONY: clean
clean:
	rm -rf bin/
