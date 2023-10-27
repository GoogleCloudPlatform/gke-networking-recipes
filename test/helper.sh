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
#   The context where the resource resides.
# Outputs:
#   Writes the ingress IP to stdout.
# Returns:
#   0 if the ingress IP is populated within 15 minutes, 1 if not.
wait_for_ingress_ip() {
    local ing ns context attempt
    ing="$1"
    ns="$2"
    context="$3"

    # 180*5s=15min
    for attempt in $(seq 180); do
        local vip
        vip=$(kubectl --context "${context}" get ingress ${ing} \
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
#   The context where the resource resides.
# Returns:
#   0 if the status of the given certificate is Active within 60 minutes, 1 if not.
wait_for_managed_cert() {
    local mc ns context attempt
    mc="$1"
    ns="$2"
    context="$3"

    # 360*10s=60min
    for attempt in $(seq 360); do
        local certStatus domainStatus status
        # Check status of the certificate.
        certStatus=$(kubectl --context "${context}" get ManagedCertificate ${mc} \
                     -n ${ns} \
                     -o jsonpath="{.status.certificateStatus}")
        if [[ "${certStatus}" != "Active" ]]; then
            sleep 10
            continue
        fi

        # Check status of each domain.
        domainStatus=( $(kubectl --context "${context}" get ManagedCertificate ${mc} \
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

# Get forwarding rule of the given ingress.
# Arguments:
#   Name of the ingress.
#   Namespace of the ingress.
#   The context where the resource resides.
# Outputs:
#   Name of http(s) forwarding rule for the ingress.
#   If both HTTP and HTTPS forwarding rules exist, this will return the HTTPS 
#   forwarding rule. If no forwarding rule exists, return "null".
get_forwarding_rule() {
    local ingress_name ns context fr
    ingress_name="$1"
    ns="$2"
    context="$3"
    fr=$(get_ing_resource "${ingress_name}" "${ns}" "${context}" "ingress.kubernetes.io/https-forwarding-rule")
    if [[ "${fr}" == "null" ]]; then 
        fr=$(get_ing_resource "${ingress_name}" "${ns}" "${context}" "ingress.kubernetes.io/forwarding-rule")
    fi        
    echo "${fr}"
}

# Get target http proxy of the given ingress.
# Arguments:
#   Name of the ingress.
#   Namespace of the ingress.
#   The context where the resource resides.
# Outputs:
#   Name of target http proxy for the ingress. If no target http proxy exists,
#   return "null".
get_target_http_proxy() {
    local ingress_name ns context thp
    ingress_name="$1"
    ns="$2"
    context="$3"
    thp=$(get_ing_resource "${ingress_name}" "${ns}" "${context}" "ingress.kubernetes.io/target-proxy")
    echo "${thp}"
}

# Get target https proxy of the given ingress.
# Arguments:
#   Name of the ingress.
#   Namespace of the ingress.
#   The context where the resource resides.
#   Name of the target https proxy for the ingress.
# Outputs:
#   Name of target https proxy for the ingress. If no target https proxy
#   exists, return "null".
get_target_https_proxy() {
    local ingress_name ns context thsp
    ingress_name="$1"
    ns="$2"
    context="$3"
    thsp=$(get_ing_resource "${ingress_name}" "${ns}" "${context}" "ingress.kubernetes.io/https-target-proxy")
    echo "${thsp}"
}

# Get url map of the given ingress.
# Arguments:
#   Name of the ingress.
#   Namespace of the ingress.
#   The context where the resource resides.
# Outputs:
#   Name of url map for the ingress. If no url map exists, return "null".
get_url_map() {
    local ingress_name ns context um
    ingress_name="$1"
    ns="$2"
    context="$3"
    um=$(get_ing_resource "${ingress_name}" "${ns}" "${context}" "ingress.kubernetes.io/url-map")
    echo "${um}"
}

# Get backend services of the given ingress.
# Arguments:
#   Name of the ingress.
#   Namespace of the ingress.
#   The context where the resource resides.
# Outputs:
#   Name of all backend services for the ingress as a string separated by new 
#   line. If no backend service exists, return "".
get_backends() {
    local ingress_name ns context backend_map
    ingress_name="$1"
    ns="$2"
    context="$3"
    backend_map=$(get_ing_resource "${ingress_name}" "${ns}" "${context}" "ingress.kubernetes.io/backends")
    backends=$(echo "${backend_map}" | jq "fromjson | keys[]")
    echo "${backends[@]}"
}

# Get the specific resource of the given ingress.
# Arguments:
#   Name of the ingress.
#   Namespace of the ingress.
#   The context where the resource resides.
#   Name of the resource in the ingress annotation.
# Output:
#   Value of the resource using annotation as key in the given ingress. If the
#   given resource does not exist, return "null".
get_ing_resource() {
    local ingress_name ns context resource_annotation resource
    ingress_name="$1"
    ns="$2"
    context="$3"
    resource_annotation="$4"
    resource=$(kubectl get ingress --context="${context}" \
                -n "${ns}" \
                -o json \
                ${ingress_name} | \
                jq ".metadata.annotations.\"${resource_annotation}\"" )
    echo "${resource}"
}

# Get names of all NEGs in the cluster.
# Arguments:
#   The context where the resource resides.
# Outputs:
#   Name of all NEGs in the cluster as a string separated by space. If no NEG
#   exists, return "".
get_negs() {
    local context resource
    context="$1"
    resource=$(kubectl get svcneg --context="${context}" \
                -o=jsonpath="{.items[*].metadata.name}" \
                -A )
    echo "${resource}"
}

# Wait for the given ingress to completely delete its resources.
# Arguments:
#   Name of forwarding rule.
#   Name of target http proxy.
#   Name of target https proxy.
#   Name of url map.
#   Name of backend services.
#   Name of NEGs.
# Returns:
#   0 if resources are deleted within 1 hour, 1 if not.
wait_for_glbc_deletion() {
    local fr thp thsp um backends negs
    fr="$1"
    thp="$2"
    thsp="$3"
    um="$4"
    backends="$5"
    negs="$6"

    local attempt
    for attempt in $(seq 360); do
        local resource
        resource=$(gcloud compute forwarding-rules list \
                    --filter="NAME=( ${fr} )" \
                    --format="value(NAME)")
        if  [[ ! -z "${resource}" ]]; then
            sleep 10
            continue
        fi

        resource=$(gcloud compute target-http-proxies list \
                    --filter="NAME=( ${thp} )" \
                    --format="value(NAME)")
        if  [[ ! -z "${resource}" ]]; then
            sleep 10
            continue
        fi

        resource=$(gcloud compute target-https-proxies list \
                    --filter="NAME=( ${thsp} )" \
                    --format="value(NAME)")
        if  [[ ! -z "${resource}" ]]; then
            sleep 10
            continue
        fi

        resource=$(gcloud compute url-maps list \
                    --filter="NAME=( ${um} )" \
                    --format="value(NAME)")
        if  [[ ! -z "${resource}" ]]; then
            sleep 10
            continue
        fi

        resource=$(gcloud compute backend-services list \
                    --filter="NAME=( ${backends} )" \
                    --format="value(NAME)")
        if  [[ ! -z "${resource}" ]]; then
            sleep 10
            continue
        fi

        resource=$(gcloud compute network-endpoint-groups list \
                    --filter="NAME=( ${negs} )" \
                    --format="value(NAME)")
        if  [[ ! -z "${resource}" ]]; then
            sleep 10
            continue
        fi
        return 0
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
#   (Optional)If curl skips verification for secure connection.
# Returns:
#   0 if the recieved HTTP response code matches the expected one within 5 minutes, 1 if not.
check_http_status() {
    local url expect_code extra_header test_name zone insecure eval_cmd
    url="$1"
    expect_code="$2"

    # Optional arguments
    extra_header="${3:-}"
    test_name="${4:-}"
    zone="${5:-}"
    insecure="${6:-}"

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

    if [[ "${insecure}" ]]; then
        eval_cmd="${eval_cmd} -k"
    fi

    # 60*5s=5min
    local attempt
    for attempt in $(seq 60); do
        local got_code
        got_code=$(eval ${eval_cmd} || true)
        if [[ "${got_code}" == "${expect_code}" ]]; then
            return 0
        fi
        sleep 5
    done
    return 1
}

# Get the Cloud OAuth brand in the project if it exists or create a new one.
# Arguments:
#   The support email for OAuth brand.
# Outputs:
#   OAuth brand name of the project.
get_or_create_oauth_brand() {
    local support_email brand
    support_email="$1"

    brand=$(gcloud iap oauth-brands list --format="value(NAME)")
    if [[ ! -z "${brand}" ]]; then
        echo "${brand}"
        return
    fi

    gcloud iap oauth-brands create --application_title="gke-net-recipes" --support_email="${support_email}"

    local attempt
    for attempt in $(seq 10); do
        brand=$(gcloud iap oauth-brands list --format="value(NAME)")
        if [[ -z "${brand}" ]]; then
            sleep 5
            continue
        fi
        break
    done
    echo "${brand}"
}

# Get the OAuth client ID and secret for the given test.
# Arguments:
#   The name of oauth_brand.
#   Name of the test. Used to generate OAuth client name.
# Outputs:
#   OAuth client name, ID, and secret.
get_oauth_client() {
    local brand test_name existing client_info client_id secret
    brand="$1"
    test_name="$2"

    existing=$(gcloud iap oauth-clients list "${brand}")
    if [[ -z "${existing}" ]]; then
        gcloud iap oauth-clients create "${brand}" --display_name="${test_name}"
    fi

    local attempt
    for attempt in $(seq 10); do
        client_info=( $(gcloud iap oauth-clients list ${brand} --format="value(NAME,SECRET)") )
        if [[ -z "${client_info[@]-}" ]]; then
            sleep 5
            continue
        fi
        break
    done
    client_id=$( echo "${client_info[0]-}" | sed 's/.*identityAwareProxyClients\/\(.*\)/\1/' )
    secret="${client_info[1]-}"
    echo "${client_info[0]-} ${client_id} ${secret}"
}
