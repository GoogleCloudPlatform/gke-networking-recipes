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
