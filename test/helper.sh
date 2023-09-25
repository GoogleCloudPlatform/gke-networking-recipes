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

# Genereate a hash of length 20 using sha1 checksum and take the first 20 characters.
# Argument:
#   Value to be hashed, a string
# Outputs:
#   Writes the hashed result to stdout.
get_hash() {
    # By default, sha1sum prints out hash and filename, so we only access the 
    # [0] element for the hash.
    local h
    h=($(echo -n $1 | sha1sum))
    echo "${h:0:20}"
}

# Wait for the given ingress to be fully provisioned.
# Argument:
#   Name of the ingress.
#   Namespace of the ingress.
# Outputs:
#   Writes the ingress IP to stdout.
# Returns:
#   0 if the ingress IP is populated within 15 minutes, 1 if not.
wait_for_ingress_ip() {
    local ing ns ATTEMPT
    ing="$1"
    ns="$2"

    # 180*5s=15min
    for ATTEMPT in $(seq 180); do
        local vip
        vip=$(kubectl get ingress ${ing} \
              -n ${ns} \
              -o jsonpath="{.status.loadBalancer.ingress[0].ip}")
        if [[ ! -z "$vip" ]]; then
            echo "${vip}"
            return 0
        fi
        sleep 5
    done
    return 1
}

# Wait for the given Managed Certificate to be fully provisioned.
# Arguments:
#   Name of the Managed Certificate.
#   Namespace of the Managed Certificate.
# Returns:
#   0 if the status of the given certificate is Active within 60 minutes, 1 if not.
wait_for_managed_cert() {
    local mc ns ATTEMPT
    mc="$1"
    ns="$2"

    # 360*10s=60min
    for ATTEMPT in $(seq 360); do
        local certStatus domainStatus status
        # Check status of the certificate.
        certStatus=$(kubectl get ManagedCertificate ${mc} \
                     -n ${ns} \
                     -o jsonpath="{.status.certificateStatus}")
        if [[ "${certStatus}" != "Active" ]]; then
            sleep 10
            continue
        fi

        # Check status of each domain.
        domainStatus=( $(kubectl get ManagedCertificate ${mc} \
                         -n ${ns} \
                         -o jsonpath="{.status.domainStatus}" | \
                         jq  ".[] | .status") )
        local count=${#domainStatus[@]}
        local match=0
        for status in "${domainStatus[@]}"; do
            if [[ "${status}" == '"Active"' ]]; then
                ((++match))
            fi
        done
        if [[ "${match}" -eq "${count}" ]]; then
            return 0
        fi
        sleep 10
    done
    return 1
}

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

# Check that the given IP responds the expected HTTP status code.
# Arguments:
#   The URL for making HTTP request to.
#   The expected HTTP status code in the reponse.
#   (Optional)An extra header to include in the request.
#   (Optional)Name of the test, will be used to genereate vm instance name. 
#             If provided, request will be sent via ssh into the test instance.
#   (Optional)Zone of the test instance.
# Returns:
#   0 if the recieved HTTP response code matches the expected one within 5 minutes, 1 if not.
check_http_status() {
    local url expect_code extra_header test_name zone eval_cmd
    url="$1"
    expect_code="$2"

    # Optional arguments
    extra_header="${3:-}"
    test_name="${4:-}"
    zone="${5:-}"

    # Get the HTTP status code from the response header.
    if [[ -z "${test_name}" ]]; then
        eval_cmd="curl -sI -o /dev/null -w \"%{http_code}\" -H \"${extra_header}\" ${url}"
    else
        local resource_suffix
        resource_suffix=$(get_hash "${test_name}")
        local resource_name="gke-net-recipes-${resource_suffix}"
        local network="${resource_name}"
        local instance="${resource_name}"

        # Create the firewall rule to allow SSH connectivity to VMs with the network tag allow-ssh.
        gcloud compute firewall-rules describe "allow-ssh-${resource_suffix}" || \
        gcloud compute firewall-rules create "allow-ssh-${resource_suffix}" \
            --network="${network}" \
            --action="allow" \
            --direction="ingress" \
            --target-tags="allow-ssh" \
            --rules="tcp:22"
        eval_cmd="gcloud compute ssh ${instance} \
                    --zone=${zone} \
                    --ssh-flag=\"-tq\" -- \
                    'curl -sI -o /dev/null -w \"%{http_code}\" -H \"${extra_header}\" ${url}'"
    fi

    # 60*5s=5min
    local ATTEMPT
    for ATTEMPT in $(seq 60); do
        local got_code
        got_code=$(eval ${eval_cmd} || true)
        if [[ "${got_code}" == "${expect_code}" ]]; then
            return 0
        fi
        sleep 5
    done
    return 1
}
