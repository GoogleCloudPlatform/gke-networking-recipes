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
context=$(get_context "${test_name}")

if [[ ! -z "${context}" ]]; then
    # TODO: Delete the k8s resources.
    # Use `|| true` to make sure the command won't failed due to resources not exist.
    kubectl --context "${context}" delete -f YOUR_YAML.yaml -n "${test_name}" || true
    kubectl --context "${context}" delete namespace "${test_name}" || true
fi

# TODO: Delete any additional resources created during setup.
# gcloud ...

cleanup_gke_basic "${test_name}" "${ZONE}" "${REGION}"
