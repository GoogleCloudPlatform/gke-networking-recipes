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

source ./test/helper.sh
source ./test/test.conf
test_name="ingress-custom-grpc-health-check"
suffix=$(get_hash "${test_name}")
context=$(kubectl config view -o json | jq -r ".contexts[] | select(.name | test(\"-${suffix}\")).name" || true)

if [[ -z "${context}" ]]; then
    exit 1
fi

xlb_ip=$(wait_for_ingress_ip "fe-ingress" "${test_name}" "${context}")
ilb_ip=$(wait_for_ingress_ip "fe-ilb-ingress" "${test_name}" "${context}")

resource_name="gke-net-recipes-${suffix}"
network="${resource_name}"
instance="${resource_name}"

repeating=10  # Number of RPC requests we are sending.
pattern="fe-deployment" # Deployment name, inclueded in the echo.EchoServer SayHello function response.

# Check ingress-grpc traffic by sending RPC request to load balancer IP,
# and look for the pattern in the response.
# Arguments:
#   Load balancer IP.
#   Number of RPC requests to send.
#   Pattern to look for in the response.
#   vm instance name. If provided, request will be sent via ssh into the instance.
check_ingress_grpc_response() {
    local vip repeating pattern instance eval_cmd ATTEMPT
    vip="$1"
    repeating="$2"
    pattern="$3"
    instance="${4:-}"
    eval_cmd="docker run \
                --add-host grpc.domain.com:${vip} \
                -t \
                docker.io/salrashid123/grpc_app /grpc_client \
                --host=grpc.domain.com:443 \
                --tlsCert /certs/CA_crt.pem  \
                --servername grpc.domain.com --repeat ${repeating} -skipHealthCheck"

    if [[ ! -z "${instance}" ]]; then
        eval_cmd="gcloud compute ssh "${instance}" --zone="${zone}" -- \
                    '{ docker --version || \
                        (curl -fsSL https://get.docker.com -o get-docker.sh && sudo sh get-docker.sh); } > /dev/null && \
                     sudo ${eval_cmd}'"
    fi

    for ATTEMPT in $(seq 60); do
        local response
        response=$(eval ${eval_cmd} || true)
        if [[ -z "${response}" ]]; then
            sleep 5
            continue
        fi

        # Wait for server and SSL certificate to be ready.
        if ! check_pattern_count "${response}" "${pattern}" "${repeating}"; then
            sleep 5
            continue
        fi
        return 0
    done
    return 1
}

check_ingress_grpc_response "${xlb_ip}" "${repeating}" "${pattern}"
check_ingress_grpc_response "${ilb_ip}" "${repeating}" "${pattern}" "${instance}"
