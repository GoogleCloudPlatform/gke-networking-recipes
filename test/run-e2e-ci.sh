
#!/bin/bash

# Copyright 2023 The Kubernetes Authors.

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#     http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# NOTE: this script ONLY works on the GKE internal Prow test pipeline.

set -o xtrace
set -o nounset
set -o errexit

readonly pkg_dir="${PKG_DIR:-src/github.com/GoogleCloudPlatform/gke-networking-recipes}"
readonly boskos_resource_type="${GCE_PD_BOSKOS_RESOURCE_TYPE:-gke-internal-project}"
readonly network_name="${NETWORK_NAME:-rcp-network}"
readonly subnet_name="${SUBNET_NAME:-rcp-subnet}"
readonly cluster_name="${CLUSTER_NAME:-rcp-cluster}"
readonly zone=${ZONE:-us-west1-a}
readonly num_nodes=${NUM_NODES:-3}

# Clean up.
rm -rf bin/

# Make test binary.
mkdir bin/
go test -c -o bin/recipes-test ./test

# Run test binary with boskos project rental.
base_cmd="bin/recipes-test \
        --pkg-dir=${pkg_dir} \
        --boskos-resource-type=${boskos_resource_type} \
        --run-in-prow=true \
        --network-name=${network_name} \
        --subnet-name=${subnet_name} \
        --cluster-name=${cluster_name} \
        --zone=${zone} \
        --num-nodes=${num_nodes} \
        --delete-cluster=true \
        -test.run=.*"

eval "$base_cmd"

