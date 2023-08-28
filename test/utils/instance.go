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

func CreateInstance(ctx context.Context, c cloud.Cloud, zone string, instance *compute.Instance) error {
	err := c.Instances().Insert(ctx, meta.ZonalKey(instance.Name, zone), instance)
	if err != nil {
		return fmt.Errorf("CreateInstance(%q, %q) failed to insert: %w", zone, instance.Name, err)
	}
	_, err = c.Instances().Get(ctx, meta.ZonalKey(instance.Name, zone))
	if err != nil {
		return fmt.Errorf("CreateInstance(%q) failed to get: %w", instance.Name, err)
	}
	return nil
}

func DeleteInstance(ctx context.Context, c cloud.Cloud, zone string, instance *compute.Instance) error {
	err := c.Instances().Delete(ctx, meta.ZonalKey(instance.Name, zone))
	if err != nil {
		if isHTTPErrorCode(err, http.StatusNotFound) {
			return nil
		}
		return fmt.Errorf("DeleteInstance(%q, %q) failed to delete: %w", zone, instance.Name, err)
	}
	_, err = c.Instances().Get(ctx, meta.ZonalKey(instance.Name, zone))
	if !isHTTPErrorCode(err, http.StatusNotFound) {
		return fmt.Errorf("DeleteInstance(%q) failed to verify deletion: %w", instance.Name, err)
	}
	klog.Infof("Instance %s deleted", instance.Name)
	return nil
}
