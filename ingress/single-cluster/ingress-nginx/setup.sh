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
test_name="ingress-nginx"
setup_gke_basic "${test_name}" "${ZONE}" "${REGION}"
context=$(get_context "${test_name}")

if [[ -z "${context}" ]]; then
    exit 1
fi

kubectl --context "${context}" create namespace "${test_name}"
kubectl --context "${context}" create clusterrolebinding cluster-admin-binding \
  --clusterrole cluster-admin \
  --user $(gcloud config get-value account)
kubectl --context "${context}" apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.1.0/deploy/static/provider/cloud/deploy.yaml

for ATTEMPT in $(seq 30); do
    if kubectl --context "${context}" apply -f ingress/single-cluster/ingress-nginx/ingress-nginx.yaml -n "${test_name}"; then
        break
    fi
    sleep 10 # Wait for webhook to be fully setup.
done
