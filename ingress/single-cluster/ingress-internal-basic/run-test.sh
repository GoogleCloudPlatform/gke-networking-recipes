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

recipe_dir=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )
source "$(find ${recipe_dir}/../../../test/ -name helper.sh)" "$@"

ilb_setup="$(find ${recipe_dir}/../../../test -name ilb_setup.sh)"
resource_yaml="$(find -name internal-ingress-basic.yaml)"
namespace="ingress-internal-basic"
kubectl create namespace "${namespace}"

# Part1. Setup ILB
bash "${ilb_setup}"

# Part2. Setup resources as described in README
kubectl apply -f "${resource_yaml}" -n "${namespace}"

echo
GCLB_IP=$(wait_for_ingress_ip "foo-internal" "${namespace}")
echo "Load balancer IP is ${GCLB_IP}"

# PART3. Validate ingress traffic
validate_ingress_traffic="$(find ${recipe_dir}/../../../test -name validate_ingress_traffic.sh)"
bash "{validate_ingress_traffic}" -p ${GCLB_IP} -c 200 -h "host: foo.example.com" -v
bash "{validate_ingress_traffic}" -p ${GCLB_IP} -c 404 -h "host: bar.example.com" -v

# PART4. Delete resources as described in README
kubectl delete -f "${resource_yaml}" -n "${namespace}"
kubectl delete namespace "${namespace}"