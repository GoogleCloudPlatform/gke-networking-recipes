/*
Copyright 2023 The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

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

func CreateFirewall(ctx context.Context, c cloud.Cloud, firewall *compute.Firewall) error {
	err := c.Firewalls().Insert(ctx, meta.GlobalKey(firewall.Name), firewall)
	if err != nil {
		return fmt.Errorf("createFirewall(%q) failed to insert: %w", firewall.Name, err)
	}
	_, err = c.Firewalls().Get(ctx, meta.GlobalKey(firewall.Name))
	if err != nil {
		return fmt.Errorf("createFirewall(%q) failed to get: %w", firewall.Name, err)
	}
	return nil
}

func DeleteFirewall(ctx context.Context, c cloud.Cloud, firewall *compute.Firewall) error {
	err := c.Firewalls().Delete(ctx, meta.GlobalKey(firewall.Name))
	if err != nil {
		if isHTTPErrorCode(err, http.StatusNotFound) {
			return nil
		}
		return fmt.Errorf("DeleteFirewall(%q) failed to delete: %w", firewall.Name, err)
	}
	_, err = c.Firewalls().Get(ctx, meta.GlobalKey(firewall.Name))
	if !isHTTPErrorCode(err, http.StatusNotFound) {
		return fmt.Errorf("DeleteFirewall(%q) failed to verify deletion: %w", firewall.Name, err)
	}
	klog.Infof("Firewall %s deleted", firewall.Name)
	return nil
}
