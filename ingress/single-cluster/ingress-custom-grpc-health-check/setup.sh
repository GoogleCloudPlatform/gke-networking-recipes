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
source ./test/test.conf
test_name="ingress-custom-grpc-health-check"
setup_gke_basic "${test_name}" "${zone}" "${subnet_region}"
setup_ilb "${test_name}" "${subnet_region}"
suffix=$(get_hash "${test_name}")
context=$(kubectl config view -o json | jq -r ".contexts[] | select(.name | test(\"-${suffix}\")).name")

if [[ -z "${context}" ]]; then
    exit 1
fi

gcloud compute ssl-policies create gke-ingress-ssl-policy-grpc \
    --profile MODERN \
    --min-tls-version 1.2

kubectl --context "${context}" create namespace "${test_name}"
kubectl --context "${context}" apply -f ingress/single-cluster/ingress-custom-grpc-health-check/example/ -n "${test_name}"
