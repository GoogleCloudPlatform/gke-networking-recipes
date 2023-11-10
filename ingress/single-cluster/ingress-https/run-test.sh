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

if [[ -z "${DNS_PROJECT-}" ||  -z "${DNS_ZONE-}" ||  -z "${DNS_NAME-}" ]]; then
    echo "Required environment variables are not set. See ingress-https/REAME.md for details."
    exit 0
fi

source ./test/helper.sh
test_name="ingress-https"
context=$(get_context "${test_name}")

if [[ -z "${context}" ]]; then
    exit 1
fi

vip=$(wait_for_ingress_ip "secure-ingress" "${test_name}" "${context}")

wait_for_managed_cert "foobar-certificate" "ingress-https" "${context}"

foo_dns_record="foo.${DNS_NAME}"
bar_dns_record="bar.${DNS_NAME}"
check_http_status "https://${foo_dns_record}" 200
check_http_status "https://${bar_dns_record}" 200
check_http_status "http://${foo_dns_record}" 301
check_http_status "http://${bar_dns_record}" 301
