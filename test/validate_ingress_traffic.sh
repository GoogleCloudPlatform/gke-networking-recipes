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

source "$(find -name helper.sh)" "$@"

ZONE="us-west1-a"
VIA_SSH=false
HOST=""
resource_suffix=$(get_hash ingress)
RESOURCE_NAME="gke-net-recipes-${resource_suffix}"

while getopts "p:c:h:vn:" var
do
    case "$var" in
        p) CURL_PATH=${OPTARG};;
        c) EXPECT_CODE=${OPTARG};;
        h) HOST=${OPTARG};;
        v) VIA_SSH=true;;
    esac
done

if ${VIA_SSH}; then
    echo "Validating via ssh..."
    gcloud compute firewall-rules describe "allow-ssh-${resource_suffix}" || gcloud compute firewall-rules create "allow-ssh-${resource_suffix}" --network="${RESOURCE_NAME}" --action="allow" --direction="ingress" --target-tags="allow-ssh" --rules="tcp:22"
    eval_cmd="gcloud compute ssh ${RESOURCE_NAME} --zone=${ZONE} --ssh-flag=\"-tq\" -- 'curl -sI -o /dev/null -w \"%{http_code}\" -H \"${HOST}\" ${CURL_PATH}'"
else
    echo "Validating directly..."
    eval_cmd="curl -sI -o /dev/null -w \"%{http_code}\" -H \"${HOST}\" ${CURL_PATH}"
fi

echo "Commmand is \"${eval_cmd}\""
for ATTEMPT in $(seq 10); do
    GOT_CODE=$(eval ${eval_cmd} || true)
    echo "Expect code ${EXPECT_CODE}, got ${GOT_CODE}"
    if [[ "${GOT_CODE}" == "${EXPECT_CODE}" ]]; then
        echo "Valiated."
        exit 0
    fi
    sleep 30
done
echo "Failed to validate ingress"
exit 1

