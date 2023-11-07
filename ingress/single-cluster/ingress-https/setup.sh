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
setup_gke_basic "${test_name}" "${ZONE}" "${REGION}"
context=$(get_context "${test_name}")

if [[ -z "${context}" ]]; then
    exit 1
fi

kubectl --context "${context}" create namespace "${test_name}"

static_ip_name=gke-foobar-public-ip
gcloud compute addresses create --global "${static_ip_name}"
static_ip=$(gcloud compute addresses describe --global "${static_ip_name}" --format="value(address)")
gcloud compute ssl-policies create gke-ingress-ssl-policy-https --profile MODERN --min-tls-version 1.2

foo_dns_record="foo.${DNS_NAME}"
bar_dns_record="bar.${DNS_NAME}"
gcloud dns --project="${DNS_PROJECT}" record-sets create "${foo_dns_record}" \
    --zone="${DNS_ZONE}" \
    --type="A" \
    --ttl="14400" \
    --rrdatas="${static_ip}"
gcloud dns --project="${DNS_PROJECT}" record-sets create "${bar_dns_record}" \
    --zone="${DNS_ZONE}" \
    --type="A" \
    --ttl="14400" \
    --rrdatas="${static_ip}"

resource_yaml="ingress/single-cluster/ingress-https/secure-ingress.yaml"
sed -i'.bak' "s/foo.\${DOMAIN}.com/${foo_dns_record}/g" "${resource_yaml}"
sed -i'.bak' "s/bar.\${DOMAIN}.com/${bar_dns_record}/g" "${resource_yaml}"
kubectl --context "${context}" apply -f "${resource_yaml}" -n "${test_name}"
