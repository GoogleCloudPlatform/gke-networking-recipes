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

source "./test/helper.sh" "$@"

# test_name="ingress-https"

# GCLB_IP=$(wait_for_ingress_ip "cloudarmor-test" "${test_name}")
# echo "Load balancer IP is ${GCLB_IP}"

# validate_traffic https://foo.bp.ing.gke.certsbridge.com. 200
# validate_traffic https://bar.bp.ing.gke.certsbridge.com. 200
# validate_traffic http://foo.bp.ing.gke.certsbridge.com. 301
# validate_traffic http://bar.bp.ing.gke.certsbridge.com. 301

wait_for_managed_cert "foobar-certificate" "ingress-https"