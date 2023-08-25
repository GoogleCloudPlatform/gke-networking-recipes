// Copyright 2023 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package utils

import (
	"fmt"
	"os/exec"
	"strconv"
	"strings"

	"k8s.io/klog/v2"
)

type ClusterConfig struct {
	Name        string
	Zone        string
	NumOfNodes  int
	NetworkName string
	SubnetName  string
}

func EnsureCluster(config ClusterConfig) error {
	if !isClusterExisting(config) {
		klog.Infof("Cluster %s in zone %s does not exist, creating.", config.Name, config.Zone)
		return createCluster(config)
	}
	if err := verifyCluster(config); err != nil {
		return fmt.Errorf("verifyCluster(%q, %q) failed: %w", config.Name, config.Zone, err)
	}
	klog.Infof("Using existing cluster %s in zone %s with %d nodes.", config.Name, config.Zone, config.NumOfNodes)
	return nil
}

func createCluster(config ClusterConfig) error {
	params := []string{
		"container",
		"clusters",
		"create",
		config.Name,
		"--zone", config.Zone,
		"--num-nodes", strconv.Itoa(config.NumOfNodes),
		"--network", config.NetworkName,
		"--subnetwork", config.SubnetName,
	}
	if out, err := exec.Command("gcloud", params...).CombinedOutput(); err != nil {
		return fmt.Errorf("createCluster(%q, %q, %d) failed: %q: %w", config.Name, config.Zone, config.NumOfNodes, out, err)
	}
	return nil
}

func DeleteCluster(config ClusterConfig) error {
	params := []string{
		"container",
		"clusters",
		"delete",
		config.Name,
		"--zone", config.Zone,
		"--quiet",
	}
	if out, err := exec.Command("gcloud", params...).CombinedOutput(); err != nil {
		return fmt.Errorf("DeleteCluster(%q, %q) failed: %q: %w", config.Name, config.Zone, out, err)
	}
	return nil
}

// GetCredentials will updates the user's cluster credentials that are saved
// in their ~/.kube/config directory and switch to the provided cluster.
func GetCredentials(config ClusterConfig) error {
	params := []string{
		"container",
		"clusters",
		"get-credentials",
		config.Name,
		"--zone", config.Zone,
	}
	if out, err := exec.Command("gcloud", params...).CombinedOutput(); err != nil {
		return fmt.Errorf("GetCredentials(%q, %q) failed: %q: %w", config.Name, config.Zone, out, err)
	}
	return nil
}

// isClusterExisting checks if the given cluster exists in the given zone.
func isClusterExisting(config ClusterConfig) bool {
	clusters := listClusters(config.Zone)
	for _, c := range clusters {
		if c == config.Name {
			return true
		}
	}
	return false
}

// listClusters lists cluster names in the given zone with Value format.
func listClusters(zone string) []string {
	params := []string{
		"container",
		"clusters",
		"list",
		"--zone", zone,
		"--format", "value(NAME)",
	}
	out, err := exec.Command("gcloud", params...).CombinedOutput()
	if err != nil {
		klog.Fatalf("listClusters(%q) failed: %q: %v", zone, out, err)
	}
	return strings.Split(string(out), "\n")
}
