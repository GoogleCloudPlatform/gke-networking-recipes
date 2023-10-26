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
test_name="ingress-cloudarmor"
setup_gke_basic "${test_name}" "${ZONE}" "${REGION}"
context=$(get_context "${test_name}")

if [[ -z "${context}" ]]; then
    exit 1
fi

kubectl --context "${context}" create namespace "${test_name}"

currentIP=$(curl -s ifconfig.me)
policy_name="allow-my-ip"
gcloud compute security-policies create "${policy_name}"
gcloud compute security-policies rules update 2147483647 \
    --security-policy "${policy_name}" \
    --action "deny-502" # Update the default policy(2147483647 is the priority value for default rule).
gcloud compute security-policies rules create 1000 \
    --security-policy "${policy_name}" \
    --src-ip-ranges "${currentIP}" \
    --action "allow"

resource_yaml="ingress/single-cluster/ingress-cloudarmor/cloudarmor-ingress.yaml"
sed -i'.bak' "s/\$POLICY_NAME/${policy_name}/g" "${resource_yaml}"
kubectl --context "${context}" apply -f "${resource_yaml}" -n "${test_name}"
