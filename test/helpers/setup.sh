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

source ./test/helpers/hash.sh

# Basic setup that works for most recipe tests.
# Create a network, and a subnet in the provided region.
# Create an instance and a cluster in the given zone with the network and 
# subnet created.
# Arguments:
#   Name of the test. Used to generate suffix for resources.
#   Zone of the cluster and vm instance.
#   Region of the subnet.
setup_gke_basic() {
    local test_name zone subnet_region resource_suffix
    test_name="$1"
    zone="$2"
    subnet_region="$3"
    resource_suffix=$(get_hash "${test_name}")

    local resource_name="gke-net-recipes-${resource_suffix}"
    local network="${resource_name}"
    local subnet="${resource_name}"
    local instance="${resource_name}"
    local cluster="${resource_name}"

    gcloud compute networks create "${network}" --subnet-mode="custom"
    gcloud compute networks subnets create "${subnet}" \
        --network="${network}" \
        --region="${subnet_region}" \
        --range="10.1.2.0/24"
    gcloud compute instances create "${instance}" \
        --zone="${zone}" \
        --network="${network}" \
        --subnet="${subnet}" \
        --image-family="debian-11" \
        --image-project="debian-cloud" \
        --tags="allow-ssh"
    gcloud container clusters create "${cluster}" \
        --zone="${zone}" \
        --network="${network}" \
        --subnetwork="${subnet}"
    gcloud container clusters get-credentials "${cluster}" --zone="${zone}"
}

# Cleanup the basic setup for recipe test.
# Delete the network, subnet, instance and cluster created in setup_gke_basic.
# Arguments:
#   Name of the test. Used to generate suffix for resources.
#   Zone of the cluster and vm instance.
#   Region of the subnet.
cleanup_gke_basic() {
    local test_name zone subnet_region resource_suffix
    test_name="$1"
    zone="$2"
    subnet_region="$3"
    resource_suffix=$(get_hash "${test_name}")
    
    local resource_name="gke-net-recipes-${resource_suffix}"
    local network="${resource_name}"
    local subnet="${resource_name}"
    local instance="${resource_name}"
    local cluster="${resource_name}"

    gcloud container clusters delete "${cluster}" \
        --zone="${zone}" --quiet || true
    gcloud compute instances delete "${instance}" \
        --zone="${zone}" --quiet || true
    gcloud compute networks subnets delete "${subnet}" \
        --region="${subnet_region}" --quiet || true
    gcloud compute networks subnets delete "proxy-only-${resource_suffix}" \
        --region="${subnet_region}" --quiet || true

    local firewalls fw
    # Cleanup the firewalls associated with the network before deleting it.
    firewalls=( $(gcloud compute firewall-rules list \
                  --filter="network=\"${network}\"" \
                  --format="value(NAME)") )
    for fw in "${firewalls[@]}"; do
        gcloud compute firewall-rules delete "${fw}" --quiet || true
    done

    gcloud compute networks delete "${network}" --quiet || true
}

# Network environment setup for internal load balancer so that the load
# balancer proxies can be deployed.
# Create a proxy-only subnet, and a firewall rule to allow connections from the
# load balancer proxies in the proxy-only subnet.
# Arguments:
#   Name of the test, used to generate subnet and firewall suffix.
#   Region of the subnet.
setup_ilb() {
    local test_name subnet_region resource_suffix
    test_name="$1"
    subnet_region="$2"
    resource_suffix=$(get_hash "${test_name}")

    local network="gke-net-recipes-${resource_suffix}"
    local proxy_only_subnet="proxy-only-${resource_suffix}"
    local allow_proxy_firewall="allow-proxy-${resource_suffix}"
    local proxy_only_subnet_range="10.129.0.0/23"

    gcloud compute networks subnets create "${proxy_only_subnet}" \
        --region="${subnet_region}" \
        --purpose="REGIONAL_MANAGED_PROXY" \
        --role="ACTIVE" \
        --network="${network}" \
        --range="${proxy_only_subnet_range}"
    gcloud compute firewall-rules create "${allow_proxy_firewall}" \
        --allow="TCP:80" \
        --source-ranges="${proxy_only_subnet_range}" \
        --network="${network}"
}

# Get the kubectl context for a test based on the test name.
# A kubectl context contains the cluster's name.
# Arguments:
#   Name of the test, used to genereate the cluster name.
# Output:
#   The context used in the given test.
get_context() {
    local test_name suffix cluster_name
    test_name="$1"
    suffix=$(get_hash "${test_name}")
    cluster_name="gke-net-recipes-${suffix}"
    context=$(kubectl config view -o json | jq -r ".contexts[] | select(.name | test(\"${cluster_name}\")).name" || true)
    echo "${context}"
}
