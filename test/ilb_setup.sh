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

ZONE="us-west1-a"
SUBNET_REGION=$(echo "${ZONE}" | sed 's/\(.*\)-.*/\1/')

resource_suffix=$(get_hash ingress)
RESOURCE_NAME="gke-net-recipes-${resource_suffix}"
proxy_only_subnet="proxy-only-${resource_suffix}"
allow_proxy_firewall="allow-proxy-${resource_suffix}"
range="10.129.0.0/23"

gcloud compute networks subnets describe "${proxy_only_subnet}" --region="${SUBNET_REGION}" || gcloud compute networks subnets create "${proxy_only_subnet}" --region="${SUBNET_REGION}" --purpose="REGIONAL_MANAGED_PROXY" --role="ACTIVE" --network="${RESOURCE_NAME}" --range="${range}"
gcloud compute firewall-rules describe "${allow_proxy_firewall}" || gcloud compute firewall-rules create "${allow_proxy_firewall}" --allow="TCP:80" --source-ranges="${range}" --network="${RESOURCE_NAME}"
