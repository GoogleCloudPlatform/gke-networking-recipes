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
source ./test/test.conf
test_name="ingress-custom-grpc-health-check"
suffix=$(get_hash "${test_name}")
context=$(kubectl config view -o json | jq -r ".contexts[] | select(.name | test(\"-${suffix}\")).name" || true)

if [[ ! -z "${context}" ]]; then
    ilb_ingress_name="fe-ilb-ingress"
    ilb_fr=$(get_forwarding_rule "${ilb_ingress_name}" "${test_name}" "${context}")
    ilb_thp=$(get_target_http_proxy "${ilb_ingress_name}" "${test_name}" "${context}")
    ilb_thsp=$(get_target_https_proxy "${ilb_ingress_name}" "${test_name}" "${context}")
    ilb_um=$(get_url_map "${ilb_ingress_name}" "${test_name}" "${context}")
    ilb_backends=$(get_backends "${ilb_ingress_name}" "${test_name}" "${context}")
    negs=$(get_negs "${context}")

    xlb_ingress_name="fe-ingress"
    xlb_fr=$(get_forwarding_rule "${xlb_ingress_name}" "${test_name}" "${context}")
    xlb_thp=$(get_target_http_proxy "${xlb_ingress_name}" "${test_name}" "${context}")
    xlb_thsp=$(get_target_https_proxy "${xlb_ingress_name}" "${test_name}" "${context}")
    xlb_um=$(get_url_map "${xlb_ingress_name}" "${test_name}" "${context}")
    xlb_backends=$(get_backends "${xlb_ingress_name}" "${test_name}" "${context}")

    kubectl --context "${context}" delete -f ingress/single-cluster/ingress-custom-grpc-health-check/example/ -n "${test_name}" || true
    wait_for_glbc_deletion "${ilb_fr}" "${ilb_thp}" "${ilb_thsp}" "${ilb_um}" "${ilb_backends}" "${negs}"
    wait_for_glbc_deletion "${xlb_fr}" "${xlb_thp}" "${xlb_thsp}" "${xlb_um}" "${xlb_backends}" "${negs}"
    kubectl --context "${context}" delete namespace "${test_name}" || true
fi

gcloud compute ssl-policies delete gke-ingress-ssl-policy-grpc --quiet || true
cleanup_gke_basic "${test_name}" "${zone}" "${subnet_region}"
