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
	"fmt"
	"net/http"

	"github.com/GoogleCloudPlatform/k8s-cloud-provider/pkg/cloud"
	"github.com/GoogleCloudPlatform/k8s-cloud-provider/pkg/cloud/meta"
	"google.golang.org/api/compute/v1"
	"k8s.io/klog/v2"
)

func EnsureSubnet(ctx context.Context, c cloud.Cloud, region string, subnet *compute.Subnetwork) (*compute.Subnetwork, error) {
	currentSubnet, err := c.Subnetworks().Get(ctx, meta.RegionalKey(subnet.Name, region))
	if err != nil {
		if isHTTPErrorCode(err, http.StatusNotFound) {
			return CreateSubnet(ctx, c, region, subnet)
		}
		return nil, fmt.Errorf("EnsureSubnet(%q) failed: %w", subnet.Name, err)
	}
	klog.Infof("Using existing subnet %s.", subnet.Name)
	return currentSubnet, nil
}

func CreateSubnet(ctx context.Context, c cloud.Cloud, region string, subnet *compute.Subnetwork) (*compute.Subnetwork, error) {
	err := c.Subnetworks().Insert(ctx, meta.RegionalKey(subnet.Name, region), subnet)
	if err != nil {
		return nil, fmt.Errorf("CreateSubnet(%q) failed to insert: %w", subnet.Name, err)
	}
	createdSubnet, err := c.Subnetworks().Get(ctx, meta.RegionalKey(subnet.Name, region))
	if err != nil {
		return nil, fmt.Errorf("CreateSubnet(%q) failed to get: %w", subnet.Name, err)
	}
	return createdSubnet, nil
}

func DeleteSubnet(ctx context.Context, c cloud.Cloud, region string, subnet *compute.Subnetwork) error {
	err := c.Subnetworks().Delete(ctx, meta.RegionalKey(subnet.Name, region))
	if err != nil {
		if isHTTPErrorCode(err, http.StatusNotFound) {
			return nil
		}
		return fmt.Errorf("DeleteSubnet(%q) failed to delete: %w", subnet.Name, err)
	}
	_, err = c.Subnetworks().Get(ctx, meta.RegionalKey(subnet.Name, region))
	if !isHTTPErrorCode(err, http.StatusNotFound) {
		return fmt.Errorf("DeleteSubnet(%q) failed to verify deletion: %w", subnet.Name, err)
	}
	klog.Infof("Subnetwork %s deleted", subnet.Name)
	return nil
}
