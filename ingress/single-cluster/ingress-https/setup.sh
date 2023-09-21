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

# set -o errexit;
# set -o nounset;
# set -o pipefail;
# set -o xtrace;

source "$(find -name helper.sh)" "$@"

test_name="ingress-https"
setup_gke_basic "${test_name}"

resource_yaml="ingress/single-cluster/ingress-https/secure-ingress.yaml"
kubectl create namespace "${test_name}"

staticIPName=gke-foobar-public-ip
gcloud compute addresses create --global "${staticIPName}"
staticIP=$(gcloud compute addresses describe --global "${staticIPName}" --format="value(address)")
gcloud compute ssl-policies create gke-ingress-ssl-policy --profile MODERN --min-tls-version 1.2
gcloud dns --project=gke-net-dns record-sets create foo.bp.ing.gke.certsbridge.com. --zone="ingress-blueprint" --type="A" --ttl="14400" --rrdatas="${staticIP}"
gcloud dns --project=gke-net-dns record-sets create bar.bp.ing.gke.certsbridge.com. --zone="ingress-blueprint" --type="A" --ttl="14400" --rrdatas="${staticIP}"

kubectl apply -f "${resource_yaml}" -n "${test_name}"
