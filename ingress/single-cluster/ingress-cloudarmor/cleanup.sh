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

source "$(find -name helper.sh)" "$@"

test_name="ingress-cloudarmor"
resource_yaml="ingress/single-cluster/ingress-cloudarmor/cloudarmor-ingress.yaml"
POLICY_NAME="allow-my-ip"

kubectl delete -f "${resource_yaml}" -n "${test_name}" || true
kubectl delete namespace "${test_name}" || true
sed -i'.bak' "s/${POLICY_NAME}/\$POLICY_NAME/g" "${resource_yaml}"
rm "${resource_yaml}".bak
gcloud compute security-policies delete "${POLICY_NAME}" --quiet || true

cleanup_gke_basic "ingress-cloudarmor"
