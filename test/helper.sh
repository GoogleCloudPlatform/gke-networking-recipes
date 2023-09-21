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

zone="us-west1-a"
subnet_region="us-west1"

# Genereate a hash of length 20 using sha1 checksum and take the first 20 characters.
get_hash() {
    # sha1sum by default prints out hash and filename, so we only access the [0] element.
    h=($(echo -n $1 | sha1sum))
    echo "${h:0:20}"
}

wait_for_ingress_ip() {
    local ing ns
    ing="$1"
    ns="$2"
    for ATTEMPT in $(seq 30); do
        vip=$(kubectl get ingress ${ing} -n ${ns} -o jsonpath="{.status.loadBalancer.ingress[0].ip}")
        if [[ ! -z "$vip" ]]; then
            echo "${vip}"
            return
        fi
        sleep 30
    done
}

wait_for_managed_cert() {
    local mc ns
    mc="$1"
    ns="$2"
    for ATTEMPT in $(seq 45); do
        certStatus=$(kubectl get ManagedCertificate ${mc} -n ${ns} -o jsonpath="{.status.certificateStatus}")
        if [[ "${certStatus}" != "Active" ]]; then
            sleep 60
            continue
        fi
        domainStatus=( $(kubectl get ManagedCertificate ${mc} -n ${ns} -o jsonpath="{.status.domainStatus[:]}") )
        for s in "${domainStatus[@]}"; do
            temp=$(echo $s | jq -r .status)
            echo $temp
        done
        exit
    done
}

setup_gke_basic() {
    local test_name
    test_name="$1"
    resource_suffix=$(get_hash "${test_name}")
    resource_name="gke-net-recipes-${resource_suffix}"

    gcloud compute networks create "${resource_name}" --subnet-mode="custom"
    gcloud compute networks subnets create "${resource_name}" --network="${resource_name}" --region="${subnet_region}" --range="10.1.2.0/24"
    gcloud compute instances create "${resource_name}" --zone="${zone}" --network="${resource_name}" --subnet="${resource_name}" --image-family="debian-11" --image-project="debian-cloud" --tags="allow-ssh"
    gcloud container clusters create "${resource_name}" --zone="${zone}" --network="${resource_name}" --subnetwork="${resource_name}"
    gcloud container clusters get-credentials "${resource_name}" --zone="${zone}"
}

cleanup_gke_basic() {
    local test_name
    test_name="$1"
    resource_suffix=$(get_hash "${test_name}")
    resource_name="gke-net-recipes-${resource_suffix}"

    gcloud container clusters delete "${resource_name}" --zone="${zone}" --quiet || true
    gcloud compute instances delete "${resource_name}" --zone="${zone}" --quiet || true
    gcloud compute networks subnets delete "${resource_name}" --region="${subnet_region}" --quiet || true

    firewalls=( $(gcloud compute firewall-rules list --filter="network=\"${resource_name}\"" --format="value(NAME)") )
    for fw in "${firewalls[@]}"; do
        echo "${fw}" | awk '{printf "gcloud compute firewall-rules delete %s --quiet\n", $1}' | bash || true
    done

    gcloud compute networks delete "${resource_name}" --quiet || true
}

setup_ilb() {
    local test_name
    test_name="$1"
    resource_suffix=$(get_hash "${test_name}")
    resource_name="gke-net-recipes-${resource_suffix}"

    proxy_only_subnet="proxy-only-${resource_suffix}"
    allow_proxy_firewall="allow-proxy-${resource_suffix}"
    proxy_only_subnet_range="10.129.0.0/23"

    gcloud compute networks subnets create "${proxy_only_subnet}" --region="${subnet_region}" --purpose="REGIONAL_MANAGED_PROXY" --role="ACTIVE" --network="${resource_name}" --range="${proxy_only_subnet_range}"
    gcloud compute firewall-rules create "${allow_proxy_firewall}" --allow="TCP:80" --source-ranges="${proxy_only_subnet_range}" --network="${resource_name}"
}

# Validate load balancer traffic by sending a curl command with given arguments.
#   Arguments:
#     arg0: URL for the HTTP request.
#     arg1: Expected HTTP status code in the reponse.
#     arg2: Extra headers to include in the request.
#     arg3: Name of the test, will be used to genereate vm instance name. 
#           If provided, request will be sent via ssh into the test instance
validate_traffic() {
    local url expect_code extra_header test_name
    url="$1"
    expect_code="$2"

    # Optional arguments
    extra_header="${3:-}"
    test_name="${4:-}"

    if [[ -z "${test_name}" ]]; then
        echo "Validating directly..."
        eval_cmd="curl -sI -o /dev/null -w \"%{http_code}\" -H \"${extra_header}\" ${url}"
    else
        echo "Validating via ssh..."
        resource_suffix=$(get_hash "${test_name}")
        resource_name="gke-net-recipes-${resource_suffix}"

        gcloud compute firewall-rules describe "allow-ssh-${resource_suffix}" || gcloud compute firewall-rules create "allow-ssh-${resource_suffix}" --network="${resource_name}" --action="allow" --direction="ingress" --target-tags="allow-ssh" --rules="tcp:22"
        eval_cmd="gcloud compute ssh ${resource_name} --zone=${zone} --ssh-flag=\"-tq\" -- 'curl -sI -o /dev/null -w \"%{http_code}\" -H \"${extra_header}\" ${url}'"
    fi

    echo "Commmand is \"${eval_cmd}\""
    for ATTEMPT in $(seq 10); do
        got_code=$(eval ${eval_cmd} || true)
        echo "Expect code ${expect_code}, got ${got_code}"
        if [[ "${got_code}" == "${expect_code}" ]]; then
            echo "Valiated."
            return
        fi
        sleep 30
    done
    echo "Failed to validate ingress"
    exit 1
}