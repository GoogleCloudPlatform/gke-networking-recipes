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

package test

import (
	"context"
	"fmt"
	"os"
	"path"
	"testing"

	"github.com/GoogleCloudPlatform/gke-networking-recipes/test/utils"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/klog/v2"
)

func TestIngressCustomDefaultBackendSingleCluster(t *testing.T) {
	ctx := context.Background()
	namespace := "ing-custom-default-be"

	// Set up proxy-only subnet and firewall for internal Ingress.
	region := framework.Region
	proxyOnlySubnet := buildProxyOnlySubnet(fmt.Sprintf("proxy-only-%s", namespace), region, framework.Network.SelfLink)
	klog.Infof("CreateSubnet(%+v)", proxyOnlySubnet)
	if _, err := utils.CreateSubnet(ctx, framework.Cloud, region, proxyOnlySubnet); err != nil {
		t.Fatalf("CreateSubnet(%s, %s) failed: %v, want nil", region, proxyOnlySubnet.Name, err)
	}
	t.Cleanup(func() {
		if err := utils.DeleteSubnet(ctx, framework.Cloud, region, proxyOnlySubnet); err != nil {
			t.Fatalf("DeleteSubnet(%s) failed: %v, want nil", proxyOnlySubnet.Name, err)
		}
	})

	allowProxyConnFw := buildAllowProxyConnectionFirewall(fmt.Sprintf("allow-proxy-%s", namespace), framework.Network.SelfLink)
	klog.Infof("CreateFirewall(%+v)", allowProxyConnFw)
	if err := utils.CreateFirewall(ctx, framework.Cloud, allowProxyConnFw); err != nil {
		t.Fatalf("CreateFirewall(%s) failed: %v, want nil", allowProxyConnFw.Name, err)
	}
	t.Cleanup(func() {
		if err := utils.DeleteFirewall(ctx, framework.Cloud, allowProxyConnFw); err != nil {
			t.Fatalf("DeleteFirewall(%s) failed: %v, want nil", allowProxyConnFw.Name, err)
		}
	})

	testInstanceName := fmt.Sprintf("allow-ssh-%s", namespace)
	// Create a test instance that in the same zone and network as the cluster.
	testInstance := buildTestInstance(testInstanceName, framework.Network.SelfLink, framework.Subnet.SelfLink, framework.Zone)
	klog.Infof("CreateInstance(%q, %+v)", framework.Zone, testInstance)
	if err := utils.CreateInstance(ctx, framework.Cloud, framework.Zone, testInstance); err != nil {
		t.Fatalf("CreateInstance(%s, %s) failed: %v, want nil", framework.Zone, testInstance.Name, err)
	}
	t.Cleanup(func() {
		if err := utils.DeleteInstance(ctx, framework.Cloud, framework.Zone, testInstance); err != nil {
			t.Fatalf("DeleteFirewall(%s) failed: %v, want nil", testInstance.Name, err)
		}
	})

	framework.RunWithSandbox("Custom Default Backend", namespace, t, func(t *testing.T, s *utils.Sandbox) {
		yamlPath := "ingress/single-cluster/ingress-custom-default-backend/ingress-custom-default-backend.yaml"
		goPath := os.Getenv("GOPATH")
		crud := utils.NewK8sCRUD(framework.Client)

		objects, err := utils.ParseK8sYamlFile(path.Join(goPath, flags.pkgDir, yamlPath))
		if err != nil {
			t.Fatalf("ParseK8sYamlFile() failed: %v, want nil", err)
		}
		namespacedObjects, err := crud.ReplaceNamespace(s.Namespace, objects...)
		if err != nil {
			t.Fatalf("ReplaceNamespace(%s) failed: %v, want nil", s.Namespace, err)
		}
		objectKeys, err := crud.CreateK8sResources(ctx, namespacedObjects...)
		if err != nil {
			t.Fatalf("CreateK8sResources() failed: %v, want nil", err)
		}

		// Fetch ingress and validate its IP is ready.
		ingressGVK := schema.GroupVersionKind{Group: "networking.k8s.io", Version: "v1", Kind: "Ingress"}
		ingressObjectKeys := objectKeys[ingressGVK]
		if len(ingressObjectKeys) != 1 {
			t.Fatalf("Expect 1 ingress, got %d", len(ingressObjectKeys))
		}
		ingressIP, err := utils.WaitForIngress(ctx, framework.Client, ingressObjectKeys[0])
		if err != nil {
			t.Fatalf("WaitForIngress(%s) failed: %v, want nil", ingressObjectKeys[0], err)
		}
		klog.Infof("Ingress IP: %s", ingressIP)

		allowSSHFw := buildAllowSSHFirewall(fmt.Sprintf("allow-ssh-%s", s.Namespace), framework.Network.SelfLink)
		klog.Infof("CreateFirewall(%+v)", allowSSHFw)
		if err := utils.CreateFirewall(ctx, framework.Cloud, allowSSHFw); err != nil {
			t.Fatalf("CreateFirewall(%s) failed: %v, want nil", allowSSHFw.Name, err)
		}
		t.Cleanup(func() {
			if err := utils.DeleteFirewall(ctx, framework.Cloud, allowSSHFw); err != nil {
				t.Fatalf("DeleteFirewall(%s) failed: %v, want nil", allowSSHFw.Name, err)
			}
		})

		// Send traffic to /foo. Should receive response from foo containers.
		addr := ingressIP + "/foo"
		checkReponse := func(response []byte) error { return validatePodName(response, "foo") }
		err = checkHTTPViaVM(addr, testInstanceName, framework.Zone, checkReponse)
		if err != nil {
			t.Fatalf("checkHTTPViaVM(%s, %s, %s) failed: %v, want nil", addr, testInstanceName, framework.Zone, err)
		}

		// Send traffic to any non-defined path. Should receive response from default-be containers.
		addr = ingressIP + "/bar"
		checkReponse = func(response []byte) error { return validatePodName(response, "default-be") }
		err = checkHTTPViaVM(addr, testInstanceName, framework.Zone, checkReponse)
		if err != nil {
			t.Fatalf("checkHTTPViaVM(%s, %s, %s) failed: %v, want nil", addr, testInstanceName, framework.Zone, err)
		}

		err = crud.DeleteK8sResources(ctx, namespacedObjects...)
		if err != nil {
			t.Fatalf("DeleteK8sResources() failed: %v, want nil", err)
		}
	})
}
