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
