#!/bin/bash

# Copyright 2024 Google LLC
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

check_cr_validation() {
    path="$1"
    fail="$2"
    crd_path="./gateway-api/config/mesh/crd/experimental" 
    set +e
    output=$(kubectl validate "${path}" --local-crds "${crd_path}"  2>&1)
    set -e

    # Check if the validation passed or failed
    if [[ "$output" == *"OK"* && "$fail" == "false" ]]; then
        echo "Validation passed."
        return 0  # Test passes
    elif [[ "$output" != *"OK"* && "$fail" == "true" ]]; then
        echo "Validation failed as expected due to fail condition."
        return 0  # Test passes because fail is true and we expect validation to fail
    else
        echo "Validation failed."
        return 1  # Test fails
    fi
}

check_cr_validation "./authz/authz-cr-validation/invalid_http_rules.yaml" "true"
check_cr_validation "./authz/authz-cr-validation/invalid_provider_deny.yaml" "true"
check_cr_validation "./authz/authz-cr-validation/invalid_provider_custom.yaml" "true"
check_cr_validation "./authz/authz-cr-validation/invalid_multiple_providers.yaml" "true"
check_cr_validation "./authz/authz-cr-validation/valid.yaml" "false"
