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
context=$(get_context "${test_name}")

if [[ ! -z "${context}" ]]; then
    ingress_name="foo-external"
    fr=$(get_forwarding_rule "${ingress_name}" "${test_name}" "${context}")
    thp=$(get_target_http_proxy "${ingress_name}" "${test_name}" "${context}")
    thsp=$(get_target_https_proxy "${ingress_name}" "${test_name}" "${context}")
    um=$(get_url_map "${ingress_name}" "${test_name}" "${context}")
    backends=$(get_backends "${ingress_name}" "${test_name}" "${context}")
    negs=$(get_negs "${context}")

    kubectl --context "${context}" delete -f ingress/single-cluster/ingress-nginx/ingress-nginx.yaml -n "${test_name}" || true
    kubectl --context "${context}" delete -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.1.0/deploy/static/provider/cloud/deploy.yaml || true
    kubectl --context "${context}" delete clusterrolebinding cluster-admin-binding || true
    wait_for_glbc_deletion "${fr}" "${thp}" "${thsp}" "${um}" "${backends}" "${negs}"
    kubectl --context "${context}" delete namespace "${test_name}" || true
fi

cleanup_gke_basic "${test_name}" "${ZONE}" "${REGION}"
