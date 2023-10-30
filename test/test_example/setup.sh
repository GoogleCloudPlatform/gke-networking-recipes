#!/bin/bash

# Copyright 2023 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -o errexit;
set -o nounset;
set -o pipefail;
set -o xtrace;

source ./test/helper.sh
# TODO: Fill in your test name here.
# test_name="TEST_NAME"
# TODO: You can use setup_gke_basic for common test setup, or define your own test setup.
# setup_gke_basic "${test_name}" "${ZONE}" "${REGION}"
context=$(get_context "${test_name}")

if [[ -z "${context}" ]]; then
    exit 1
fi

kubectl --context "${context}" create namespace "${test_name}"
# TODO: Add any addition setup if needed(gcloud, kubectl, etc.), and deploy the k8s resources.
# gcloud ...
# kubectl --context "${context}" apply -f YOUR_YAML.yaml -n "${test_name}"
