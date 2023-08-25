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
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os/exec"
	"strings"

	"github.com/GoogleCloudPlatform/k8s-cloud-provider/pkg/cloud"
	"golang.org/x/oauth2/google"
	alpha "google.golang.org/api/compute/v0.alpha"
	beta "google.golang.org/api/compute/v0.beta"
	"google.golang.org/api/compute/v1"
	"google.golang.org/api/googleapi"
)

func newCloud(project string) (cloud.Cloud, error) {
	ctx := context.Background()
	client, err := google.DefaultClient(ctx, compute.ComputeScope)
	if err != nil {
		return nil, err
	}

	alpha, err := alpha.New(client)
	if err != nil {
		return nil, err
	}
	beta, err := beta.New(client)
	if err != nil {
		return nil, err
	}
	ga, err := compute.New(client)
	if err != nil {
		return nil, err
	}

	svc := &cloud.Service{
		GA:            ga,
		Alpha:         alpha,
		Beta:          beta,
		ProjectRouter: &cloud.SingleProjectRouter{ID: project},
		RateLimiter:   &cloud.NopRateLimiter{},
	}

	theCloud := cloud.NewGCE(svc)
	return theCloud, nil
}

// verifyCluster checks if the cluster description has the expected configuration.
func verifyCluster(config ClusterConfig) error {
	// Verify if the cluster has the correct currentNodeCount.
	params := []string{
		"container",
		"clusters",
		"describe",
		config.Name,
		"--zone", config.Zone,
		"--format", "json(currentNodeCount, network, subnetwork)",
	}
	out, err := exec.Command("gcloud", params...).CombinedOutput()
	if err != nil {
		return fmt.Errorf("cannot describe cluster %q using gcloud: %w", config.Name, err)
	}

	jsonStruct := struct {
		CurrenNodeCount int    `json:"currentNodeCount"`
		Network         string `json:"network"`
		Subnetwork      string `json:"subnetwork"`
	}{}

	err = json.Unmarshal(out, &jsonStruct)
	if err != nil {
		return fmt.Errorf("cannot unmarshal description %q into json: %w", out, err)
	}
	if config.NumOfNodes != jsonStruct.CurrenNodeCount {
		return fmt.Errorf("expect cluster %q to have %d nodes, got %d nodes", config.Name, config.NumOfNodes, jsonStruct.CurrenNodeCount)
	}
	if config.NetworkName != jsonStruct.Network {
		return fmt.Errorf("expect cluster %q to be in network %q, got network %s", config.Name, config.NetworkName, jsonStruct.Network)
	}
	if config.SubnetName != jsonStruct.Subnetwork {
		return fmt.Errorf("expect cluster %q to be in subnetwork %q, got subnetwork %s", config.Name, config.SubnetName, jsonStruct.Subnetwork)
	}
	return nil
}

// isHTTPErrorCode checks if the given error matches the given HTTP Error code.
// For this to work the error must be a googleapi Error.
func isHTTPErrorCode(err error, code int) bool {
	var apiErr *googleapi.Error
	return errors.As(err, &apiErr) && apiErr.Code == code
}

// getRegionFromZone extracts the region based on a full-qualified zone name.
// The fully-qualified name for a zone is made up of <region>-<zone>.
// (https://cloud.google.com/compute/docs/regions-zones#identifying_a_region_or_zone)
func getRegionFromZone(zone string) string {
	tokens := strings.Split(zone, "-")
	if len(tokens) < 2 {
		return ""
	}
	return strings.Join(tokens[:len(tokens)-1], "-")
}

func buildTestNetwork(networkName string) *compute.Network {
	return &compute.Network{
		Name:                  networkName,
		AutoCreateSubnetworks: false,
		// Explicitly specify false for AutoCreateSubnetworks
		// so the created network is a custom-mode VPC network.
		ForceSendFields: []string{"Name", "AutoCreateSubnetworks"},
	}
}

func buildTestSubnet(subnetName, networkLink string) *compute.Subnetwork {
	return &compute.Subnetwork{
		Name:        subnetName,
		Network:     networkLink,
		IpCidrRange: "10.1.2.0/24",
	}
}
