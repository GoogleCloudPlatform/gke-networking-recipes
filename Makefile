# Copyright 2023 Google LLC
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
ZONE ?= us-central1-c
NUM_NODES ?= 3
TEST_GOFILES := $(shell find ./test -name \*.go)
JOB_NAME ?= gke-networking-recipe-e2e

all: bin/recipes-test

bin:
	mkdir ./bin

bin/recipes-test: bin $(TEST_GOFILES)
	go test -c -o $@ ./test

.PHONY: test
test: bin/recipes-test
	bin/recipes-test \
		--run-in-prow=$(RUN_IN_PROW) \
		--boskos-resource-type=$(BOSKOS_RESOURCE_TYPE) \
		--test-project-id=$(PROJECT_ID) \
		--cluster-name=$(CLUSTER_NAME) \
		--zone=$(ZONE) \
		--num-nodes=$(NUM_NODES) \
		-test.v

.PHONY: clean
clean:
	rm -rf ./bin
