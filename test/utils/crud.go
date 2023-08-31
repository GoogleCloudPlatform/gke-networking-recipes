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

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime/schema"
	v1 "k8s.io/ingress-gce/pkg/apis/backendconfig/v1"
	backendconfigclient "k8s.io/ingress-gce/pkg/backendconfig/client/clientset/versioned"
	"k8s.io/klog/v2"
	ctrlClient "sigs.k8s.io/controller-runtime/pkg/client"
)

type Crud struct {
	c  ctrlClient.Client
	bc *backendconfigclient.Clientset
}

func NewCrud(c ctrlClient.Client, bc *backendconfigclient.Clientset) *Crud {
	return &Crud{c: c, bc: bc}
}

// CreateK8sResources creates all kubernetes resources within the given list.
func (crud *Crud) CreateK8sResources(ctx context.Context, objects ...ctrlClient.Object) (map[schema.GroupVersionKind][]ctrlClient.ObjectKey, error) {
	klog.Info("Creating K8s resources.")

	objectKeys := make(map[schema.GroupVersionKind][]ctrlClient.ObjectKey)
	for _, obj := range objects {
		gvk, err := crud.createK8sObject(ctx, obj)
		if err != nil {
			return nil, err
		}
		objectKeys[gvk] = append(objectKeys[gvk], ctrlClient.ObjectKeyFromObject(obj))
		klog.Infof("Created %s %s/%s", gvk, obj.GetNamespace(), obj.GetName())
	}
	return objectKeys, nil
}

// createK8sObject saves the object obj in the Kubernetes cluster.
func (crud *Crud) createK8sObject(ctx context.Context, obj ctrlClient.Object) (schema.GroupVersionKind, error) {
	gvk := obj.GetObjectKind().GroupVersionKind()
	if err := crud.c.Create(ctx, obj); err != nil {
		return gvk, fmt.Errorf("failed to create %s %s/%s: %w", gvk, obj.GetNamespace(), obj.GetName(), err)
	}
	return gvk, nil
}

func (crud *Crud) CreateBackendConfig(ctx context.Context, BeConfigs ...v1.BackendConfig) error {
	for _, obj := range BeConfigs {
		_, err := crud.bc.CloudV1().BackendConfigs(obj.Namespace).Create(ctx, &obj, metav1.CreateOptions{})
		if err != nil {
			return err
		}
		klog.Infof("Created %s %s/%s", obj.GroupVersionKind(), obj.GetNamespace(), obj.GetName())
	}
	return nil
}

// DeleteK8sResources deletes all kubernetes resources within the given list.
func (crud *Crud) DeleteK8sResources(ctx context.Context, objects ...ctrlClient.Object) error {
	klog.Info("Deleting K8s resources.")

	for _, obj := range objects {
		if err := crud.deleteK8sObject(ctx, obj); err != nil {
			return err
		}
	}
	return nil
}

// deleteK8sObject deletes the given obj from Kubernetes cluster.
func (crud *Crud) deleteK8sObject(ctx context.Context, obj ctrlClient.Object) error {
	gvk := obj.GetObjectKind().GroupVersionKind()
	if err := crud.c.Delete(ctx, obj); err != nil {
		return fmt.Errorf("failed to delete %s %s/%s: %w", gvk.String(), obj.GetNamespace(), obj.GetName(), err)
	}
	klog.Infof("Deleted %s %s/%s", gvk, obj.GetNamespace(), obj.GetName())
	return nil
}

func (crud *Crud) DeleteBackendConfig(ctx context.Context, BeConfigs ...v1.BackendConfig) error {
	for _, obj := range BeConfigs {
		if err := crud.bc.CloudV1().BackendConfigs(obj.Namespace).Delete(ctx, obj.Name, metav1.DeleteOptions{}); err != nil {
			return err
		}
	}
	return nil
}

// ReplaceNamespace makes a copy of the given resources, and return a new list of resources with namespace.
// Namespace won't be added for resources without namespace.
func (crud *Crud) ReplaceNamespace(namespace string, objects *ParsedObjects) (*ParsedObjects, error) {
	klog.Infof("Replace K8s resources to use namespace %s.", namespace)

	namespacedObjects := NewParsedObjects()
	for _, obj := range objects.K8sObjects {
		// Make a copy so we don't modify the original object.
		obj = obj.DeepCopyObject().(ctrlClient.Object)

		isNamespaced, err := crud.c.IsObjectNamespaced(obj)
		if err != nil {
			return nil, err
		}
		if isNamespaced {
			obj.SetNamespace(namespace)
		}
		namespacedObjects.K8sObjects = append(namespacedObjects.K8sObjects, obj)
	}
	for _, obj := range objects.BeConfigs {
		copiedObj := obj.DeepCopyObject().(*v1.BackendConfig)
		copiedObj.Namespace = namespace
		namespacedObjects.BeConfigs = append(namespacedObjects.BeConfigs, *copiedObj)
	}
	return namespacedObjects, nil
}
