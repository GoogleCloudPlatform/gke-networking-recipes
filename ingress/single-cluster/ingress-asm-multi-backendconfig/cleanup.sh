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

if [[ ! -z "${context}" ]]; then
    ingress_name="cloudarmor-test"
    fr=$(get_forwarding_rule "${ingress_name}" "${test_name}" "${context}")
    thp=$(get_target_http_proxy "${ingress_name}" "${test_name}" "${context}")
    thsp=$(get_target_https_proxy "${ingress_name}" "${test_name}" "${context}")
    um=$(get_url_map "${ingress_name}" "${test_name}" "${context}")
    backends=$(get_backends "${ingress_name}" "${test_name}" "${context}")
    negs=$(get_negs "${context}")

    kubectl --context "${context}" delete \
            -n "${test_name}" \
            -f ingress/single-cluster/ingress-asm-multi-backendconfig/backend-services.yaml \
            -f ingress/single-cluster/ingress-asm-multi-backendconfig/istio-ingressgateway-service.yaml \
            -f ingress/single-cluster/ingress-asm-multi-backendconfig/asm/samples/gateways/istio-ingressgateway/serviceaccount.yaml \
            -f ingress/single-cluster/ingress-asm-multi-backendconfig/asm/samples/gateways/istio-ingressgateway/role.yaml \
            -f ingress/single-cluster/ingress-asm-multi-backendconfig/asm/samples/gateways/istio-ingressgateway/deployment.yaml

    kubectl --context "${context}" label namespace "${test_name}" istio-injection- || true
    kubectl --context "${context}" delete secret my-cert my-secret -n "${test_name}" || true
    wait_for_glbc_deletion "${fr}" "${thp}" "${thsp}" "${um}" "${backends}" "${negs}"
    kubectl --context "${context}" delete namespace "${test_name}" || true
fi

brand=$(get_or_create_oauth_brand "${SUPPORT_EMAIL}")
result=( $(get_oauth_client "${brand}" "${test_name}") )
oauth_client_name="${result[0]}"
gcloud iap oauth-clients delete "${oauth_client_name}" --brand="${brand}" --quiet || true

rm -rf key.pem \
       certificate.pem \
       ingress/single-cluster/ingress-asm-multi-backendconfig/asm \
       ingress/single-cluster/ingress-asm-multi-backendconfig/asmcli \
       istio-1.19.3/

# We can still use this cleanup since the cluster is created with the same naming schema.
cleanup_gke_basic "${test_name}" "${ZONE}" "${REGION}"
