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

BOSKOS_RESOURCE_TYPE ?= gke-internal-project
RUN_IN_PROW ?= false
TEST_GOFILES := $(shell find ./test -name \*.go)

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
		-test.v \
		-test.timeout=180m

.PHONY: clean
clean:
	rm -rf ./bin
