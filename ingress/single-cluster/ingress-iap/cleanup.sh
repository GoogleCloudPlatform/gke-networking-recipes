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

if [[ -z "${DNS_PROJECT-}" ||  -z "${DNS_ZONE-}" ||  -z "${DNS_NAME-}" || -z "${SUPPORT_EMAIL-}" ]]; then
    echo "Required environment variables are not set. See ingress-iap/REAME.md for details."
    exit 0
fi

source ./test/helper.sh
test_name="ingress-iap"
context=$(get_context "${test_name}")

iap_dns_record="iap.${DNS_NAME}"

if [[ ! -z "${context}" ]]; then
    ingress_name="iap-test"
    fr=$(get_forwarding_rule "${ingress_name}" "${test_name}" "${context}")
    thp=$(get_target_http_proxy "${ingress_name}" "${test_name}" "${context}")
    thsp=$(get_target_https_proxy "${ingress_name}" "${test_name}" "${context}")
    um=$(get_url_map "${ingress_name}" "${test_name}" "${context}")
    backends=$(get_backends "${ingress_name}" "${test_name}" "${context}")
    negs=$(get_negs "${context}")

    resource_yaml="ingress/single-cluster/ingress-iap/iap-ingress.yaml"
    kubectl --context "${context}" delete -f "${resource_yaml}" -n "${test_name}" || true
    sed -i'.bak' "s/${iap_dns_record}/\$DOMAIN/g" "${resource_yaml}"
    rm -f "${resource_yaml}".bak
    wait_for_glbc_deletion "${fr}" "${thp}" "${thsp}" "${um}" "${backends}" "${negs}"

    kubectl --context "${context}" delete secret iap-test -n "${test_name}" || true
    kubectl --context "${context}" delete namespace "${test_name}" || true
fi

brand=$(get_or_create_oauth_brand "${SUPPORT_EMAIL}")
result=( $(get_oauth_client "${brand}" "${test_name}") )
oauth_client_name="${result[0]}"
gcloud iap oauth-clients delete "${oauth_client_name}" --brand="${brand}" --quiet || true
gcloud compute addresses delete --global "iap-test" --quiet || true
gcloud dns --project="${DNS_PROJECT}" record-sets delete "${iap_dns_record}" \
    --zone="${DNS_ZONE}" \
    --type="A" || true

cleanup_gke_basic "${test_name}" "${ZONE}" "${REGION}"
