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
setup_gke_basic "${test_name}" "${ZONE}" "${REGION}"
context=$(get_context "${test_name}")

if [[ -z "${context}" ]]; then
    exit 1
fi

kubectl --context "${context}" create namespace "${test_name}"

static_ip_name="iap-test"
gcloud compute addresses create --global "${static_ip_name}"
static_ip=$(gcloud compute addresses describe --global "${static_ip_name}" --format="value(address)")

iap_dns_record="iap.${DNS_NAME}"
gcloud dns --project="${DNS_PROJECT}" record-sets create "${iap_dns_record}" \
    --zone="${DNS_ZONE}" \
    --type="A" \
    --ttl="14400" \
    --rrdatas="${static_ip}"

brand=$(get_or_create_oauth_brand "${SUPPORT_EMAIL}")
result=( $(get_oauth_client "${brand}" "${test_name}") )
client_id="${result[1]}"
secret="${result[2]}"

kubectl --context "${context}" create secret generic iap-test \
   --from-literal=client_id="${client_id}" \
   --from-literal=client_secret="${secret}" \
   -n "${test_name}"

resource_yaml="ingress/single-cluster/ingress-iap/iap-ingress.yaml"
sed -i'.bak' "s/\$DOMAIN/${iap_dns_record}/g" "${resource_yaml}"
kubectl --context "${context}" apply -f "${resource_yaml}" -n "${test_name}"
