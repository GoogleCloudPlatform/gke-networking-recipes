#!/bin/bash

# Copyright 2023 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http:#www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


while getopts "n:s:c:z:" var
do
   case "$var" in
       n) NETWORK_NAME=${OPTARG};;
       s) SUBNET_NAME=${OPTARG};;
       c) CLUSTER_NAME=${OPTARG};;
       z) ZONE=${OPTARG};;
   esac
done

if [[ -z ${NETWORK_NAME} ]]; then 
    echo "NETWORK_NAME not set"
    exit
fi

if [[ -z ${SUBNET_NAME} ]]; then 
    echo "SUBNET_NAME not set"
    exit
fi

if [[ -z ${CLUSTER_NAME} ]]; then 
    echo "CLUSTER_NAME not set"
    exit
fi

if [[ -z ${ZONE} ]]; then 
    echo "ZONE not set"
    exit
fi

gcloud container clusters delete ${CLUSTER_NAME} --zone=${ZONE} --quiet || true

REGION=$(echo $ZONE | sed 's/\(.*\)-.*/\1/')
gcloud compute networks subnets delete ${SUBNET_NAME} --region=${REGION} --quiet || true

gcloud compute firewall-rules list --filter="network=${NETWORK_NAME}" 2> /dev/null | tail -n +2 | awk '{printf "gcloud compute firewall-rules delete %s --quiet\n", $1}' | bash

gcloud compute networks delete ${NETWORK_NAME} --quiet || true