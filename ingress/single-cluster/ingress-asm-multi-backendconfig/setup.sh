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

project=$( gcloud config get-value project 2>&1 | head -n 1 )
suffix=$(get_hash "${test_name}")
resource_name="gke-net-recipes-${suffix}"
network="${resource_name}"
subnet="${resource_name}"
instance="${resource_name}"
cluster="${resource_name}"
gcloud compute networks create "${network}" --subnet-mode="custom"
gcloud compute networks subnets create "${subnet}" \
    --network="${network}" \
    --region="${REGION}" \
    --range="10.1.2.0/24"
gcloud compute instances create "${instance}" \
    --zone="${ZONE}" \
    --network="${network}" \
    --subnet="${subnet}" \
    --image-family="debian-11" \
    --image-project="debian-cloud" \
    --tags="allow-ssh"
gcloud container clusters create "${cluster}" \
    --zone="${ZONE}" \
    --enable-ip-alias \
    --machine-type="e2-standard-4" \
    --workload-pool="${project}.svc.id.goog" \
    --release-channel rapid \
    --network="${network}" \
    --subnetwork="${subnet}"
gcloud container clusters get-credentials "${cluster}" --zone="${ZONE}"
context=$(get_context "${test_name}")

if [[ -z "${context}" ]]; then
    exit 1
fi

kubectl --context "${context}" create namespace "${test_name}"

# Install Gateway CRD with istioctl.
curl -L https://istio.io/downloadIstio | sh -
export PATH=$PWD/istio-1.19.3/bin:$PATH
istioctl install --set profile=demo -y

# Install ASM CLI.
asmcli="ingress/single-cluster/ingress-asm-multi-backendconfig/asmcli"
curl https://storage.googleapis.com/csm-artifacts/asm/asmcli_1.18 > "${asmcli}"
chmod +x "${asmcli}"

# Install ASM into the cluster.
echo "y" | ./"${asmcli}" install \
    --project_id "${project}" \
    --cluster_location us-west1-a \
    --cluster_name "${cluster}" \
    --enable_all \
    --output_dir "ingress/single-cluster/ingress-asm-multi-backendconfig/asm"

brand=$(get_or_create_oauth_brand "${SUPPORT_EMAIL}")
result=( $(get_oauth_client "${brand}" "${test_name}") )
client_id="${result[1]}"
secret="${result[2]}"

kubectl --context "${context}" create secret generic my-secret \
   --from-literal=client_id="${client_id}" \
   --from-literal=client_secret="${secret}" \
   -n "${test_name}"

openssl req -newkey rsa:2048 -nodes \
            -keyout key.pem -x509 \
            -days 365 -out certificate.pem \
            -subj "/CN=foo.example.com" \
            -addext "subjectAltName=DNS:foo.example.com,DNS:bar.example.com"
kubectl --context "${context}" create secret tls my-cert \
    --key=key.pem \
    --cert=certificate.pem \
    -n "${test_name}"

kubectl --context "${context}" label namespace "${test_name}" istio-injection=enabled --overwrite
kubectl --context "${context}" apply \
        -n "${test_name}" \
        -f ingress/single-cluster/ingress-asm-multi-backendconfig/asm/samples/gateways/istio-ingressgateway/serviceaccount.yaml \
        -f ingress/single-cluster/ingress-asm-multi-backendconfig/asm/samples/gateways/istio-ingressgateway/role.yaml \
        -f ingress/single-cluster/ingress-asm-multi-backendconfig/asm/samples/gateways/istio-ingressgateway/deployment.yaml \
        -f ingress/single-cluster/ingress-asm-multi-backendconfig/istio-ingressgateway-service.yaml
