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
