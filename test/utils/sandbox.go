/*
Copyright 2018 The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package utils

import (
	"fmt"
	"os/exec"
	"sync"

	"k8s.io/klog/v2"
)

// Sandbox represents a sandbox for running tests in a Kubernetes cluster.
type Sandbox struct {
	// Namespace to create resources in. Resources created in this namespace
	// will be deleted with Destroy().
	Namespace string

	lock      sync.Mutex
	f         *Framework
	destroyed bool
}

// Create the sandbox.
func (s *Sandbox) Create(namespace string) error {
	params := []string{
		"create",
		"namespace",
		namespace,
	}
	if out, err := exec.Command("kubectl", params...).CombinedOutput(); err != nil {
		return fmt.Errorf("failed to create namespace %s: %s, err: %v", namespace, out, err)
	}
	return nil
}

// Destroy the sandbox and all resources associated with the sandbox.
func (s *Sandbox) Destroy(namespace string) {
	s.lock.Lock()
	defer s.lock.Unlock()

	if s.destroyed {
		return
	}
	klog.Infof("Destroying test sandbox %q", s.Namespace)

	params := []string{
		"delete",
		"namespace",
		namespace,
	}
	if out, err := exec.Command("kubectl", params...).CombinedOutput(); err != nil {
		klog.Errorf("failed to delete namespace %s: %s, err: %v", namespace, out, err)
	}
	s.destroyed = true
}
