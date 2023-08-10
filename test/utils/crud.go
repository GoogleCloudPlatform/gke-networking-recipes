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

	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/klog/v2"
	ctrlClient "sigs.k8s.io/controller-runtime/pkg/client"
)

type K8sCRUD struct {
	c ctrlClient.Client
}

func NewK8sCRUD(c ctrlClient.Client) *K8sCRUD {
	return &K8sCRUD{c: c}
}

// CreateK8sResources creates all kubernetes resources within the given list.
func (crud *K8sCRUD) CreateK8sResources(ctx context.Context, objects ...ctrlClient.Object) (map[schema.GroupVersionKind][]ctrlClient.ObjectKey, error) {
	klog.Info("Creating K8s resources.")

	objectKeys := make(map[schema.GroupVersionKind][]ctrlClient.ObjectKey)
	for _, obj := range objects {
		gvk, err := crud.create(ctx, obj)
		if err != nil {
			return nil, err
		}
		objectKeys[gvk] = append(objectKeys[gvk], ctrlClient.ObjectKeyFromObject(obj))
	}
	return objectKeys, nil
}

// Create saves the object obj in the Kubernetes cluster.
func (crud *K8sCRUD) create(ctx context.Context, obj ctrlClient.Object) (schema.GroupVersionKind, error) {
	gvk := obj.GetObjectKind().GroupVersionKind()
	if err := crud.c.Create(ctx, obj); err != nil {
		return gvk, fmt.Errorf("failed to create %s %s/%s: %w", gvk, obj.GetNamespace(), obj.GetName(), err)
	}
	klog.Infof("Created %s %s/%s", gvk, obj.GetNamespace(), obj.GetName())
	return gvk, nil
}

// DeleteK8sResources deletes all kubernetes resources within the given list.
func (crud *K8sCRUD) DeleteK8sResources(ctx context.Context, objects ...ctrlClient.Object) error {
	klog.Info("Deleting K8s resources.")

	for _, obj := range objects {
		if err := crud.delete(ctx, obj); err != nil {
			return err
		}
	}
	return nil
}

// Delete deletes the given obj from Kubernetes cluster.
func (crud *K8sCRUD) delete(ctx context.Context, obj ctrlClient.Object) error {
	gvk := obj.GetObjectKind().GroupVersionKind()
	if err := crud.c.Delete(ctx, obj); err != nil {
		return fmt.Errorf("failed to delete %s %s/%s: %w", gvk.String(), obj.GetNamespace(), obj.GetName(), err)
	}
	klog.Infof("Deleted %s %s/%s", gvk, obj.GetNamespace(), obj.GetName())
	return nil
}

// ReplaceNamespace makes a copy of the given resources, and return a new list of resources with namespace.
// Namespace won't be added for resources without namespace.
func (crud *K8sCRUD) ReplaceNamespace(namespace string, objects ...ctrlClient.Object) ([]ctrlClient.Object, error) {
	klog.Info("Replace K8s resources to use namespace %s.", namespace)

	var namespacedObject []ctrlClient.Object
	for _, obj := range objects {
		// Make a copy so we don't modify the original object.
		obj = obj.DeepCopyObject().(ctrlClient.Object)

		isNamespaced, err := crud.c.IsObjectNamespaced(obj)
		if err != nil {
			return nil, err
		}
		if isNamespaced {
			obj.SetNamespace(namespace)
		}
		namespacedObject = append(namespacedObject, obj)
	}
	return namespacedObject, nil
}
