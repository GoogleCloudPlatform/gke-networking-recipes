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
#   0 if the recieved HTTP response code matches the expected one within 15 minutes, 1 if not.
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

    # 180*5s=15min
    local attempt
    for attempt in $(seq 180); do
        local got_code
        got_code=$(eval ${eval_cmd} || true)
        if [[ "${got_code}" == "${expect_code}" ]]; then
            return 0
        fi
        sleep 5
    done
    return 1
}
