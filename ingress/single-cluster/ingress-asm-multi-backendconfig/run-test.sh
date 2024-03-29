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

if [[ -z "${SUPPORT_EMAIL-}" ]]; then
    echo "Required environment variable is not set. See ingress-asm-multi-backendconfig/REAME.md for details."
    exit 0
fi

source ./test/helper.sh
test_name="ingress-asm-multi-backendconfig"
context=$(get_context "${test_name}")

if [[ -z "${context}" ]]; then
    exit 1
fi

vip=$(wait_for_ingress_ip "ingressgateway" "${test_name}" "${context}")
check_http_status "${vip}" 404

kubectl --context "${context}" apply -f ingress/single-cluster/ingress-asm-multi-backendconfig/backend-services.yaml -n "${test_name}"
check_http_status "${vip}" 200 "host: foo.example.com"
check_http_status "${vip}" 302 "host: bar.example.com"
