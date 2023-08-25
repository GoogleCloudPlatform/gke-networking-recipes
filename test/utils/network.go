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

func ensureNetwork(ctx context.Context, c cloud.Cloud, network *compute.Network) (*compute.Network, error) {
	currentNetwork, err := c.Networks().Get(ctx, meta.GlobalKey(network.Name))
	if err != nil {
		if isHTTPErrorCode(err, http.StatusNotFound) {
			return createNetwork(ctx, c, network)
		}
		return nil, fmt.Errorf("ensureNetwork(%q) failed: %w", network.Name, err)
	}
	klog.Infof("Using existing network %s.", network.Name)
	return currentNetwork, nil
}

func createNetwork(ctx context.Context, c cloud.Cloud, network *compute.Network) (*compute.Network, error) {
	err := c.Networks().Insert(ctx, meta.GlobalKey(network.Name), network)
	if err != nil {
		return nil, fmt.Errorf("createNetwork(%q) failed to insert: %w", network.Name, err)
	}
	createdNetwork, err := c.Networks().Get(ctx, meta.GlobalKey(network.Name))
	if err != nil {
		return nil, fmt.Errorf("createNetwork(%q) failed to get: %w", network.Name, err)
	}
	return createdNetwork, nil
}
