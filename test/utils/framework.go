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
	"sync"
	"testing"

	"github.com/GoogleCloudPlatform/k8s-cloud-provider/pkg/cloud"
	"google.golang.org/api/compute/v1"
	"k8s.io/client-go/rest"
	backendconfigclient "k8s.io/ingress-gce/pkg/backendconfig/client/clientset/versioned"
	frontendconfigclient "k8s.io/ingress-gce/pkg/frontendconfig/client/clientset/versioned"
	"k8s.io/klog/v2"
	ctrlClient "sigs.k8s.io/controller-runtime/pkg/client"
	ctrlLog "sigs.k8s.io/controller-runtime/pkg/log"
)

// Options for the test framework.
type Options struct {
	Project          string
	Zone             string
	NetworkName      string
	SubnetName       string
	DestroySandboxes bool
}

type Framework struct {
	Client               ctrlClient.Client
	BackendConfigClient  *backendconfigclient.Clientset
	FrontendConfigClient *frontendconfigclient.Clientset
	Cloud                cloud.Cloud
	Zone                 string
	Region               string
	Network              *compute.Network
	Subnet               *compute.Subnetwork
	lock                 sync.Mutex
	sandboxes            []*Sandbox
	destroySandboxes     bool
}

func NewFramework(config *rest.Config, options Options) *Framework {
	ctrlLog.SetLogger(klog.NewKlogr())
	client, err := ctrlClient.New(config, ctrlClient.Options{})
	if err != nil {
		klog.Fatalf("Failed to create kubernetes client: %v", err)
	}
	cloud, err := newCloud(options.Project)
	if err != nil {
		klog.Fatalf("Error creating compute client for project %q: %v", options.Project, err)
	}

	network := buildTestNetwork(options.NetworkName)
	klog.Infof("ensureNetwork(%+v)", network)
	createdNetwork, err := ensureNetwork(context.TODO(), cloud, network)
	if err != nil {
		klog.Fatalf("ensureNetwork(%+v) = %v, want nil", network, err)
	}

	// Ensure a subnet exists in the zone of the cluster.
	region := getRegionFromZone(options.Zone)
	subnet := buildTestSubnet(options.SubnetName, createdNetwork.SelfLink)
	klog.Infof("EnsureSubnet(%+v)", subnet)
	createdSubnet, err := EnsureSubnet(context.TODO(), cloud, region, subnet)
	if err != nil {
		klog.Fatalf("EnsureSubnet(%q, %+v) = %v, want nil", options.Zone, subnet, err)
	}

	return &Framework{
		Client:               client,
		FrontendConfigClient: frontendconfigclient.NewForConfigOrDie(config),
		BackendConfigClient:  backendconfigclient.NewForConfigOrDie(config),
		Zone:                 options.Zone,
		Region:               region,
		Cloud:                cloud,
		Network:              createdNetwork,
		Subnet:               createdSubnet,
		destroySandboxes:     options.DestroySandboxes,
	}
}

// RunWithSandbox runs the testFunc with the Sandbox, taking care of resource
// cleanup and isolation. This indirectly calls testing.T.Run().
func (f *Framework) RunWithSandbox(desc, namespace string, t *testing.T, testFunc func(*testing.T, *Sandbox)) {
	t.Run(desc, func(t *testing.T) {
		f.lock.Lock()
		sandbox := &Sandbox{
			Namespace: namespace,
			f:         f,
		}
		for _, s := range f.sandboxes {
			if s.Namespace == sandbox.Namespace {
				f.lock.Unlock()
				t.Fatalf("Sandbox %s was created previously by the framework.", s.Namespace)
			}
		}
		klog.V(2).Infof("Using namespace %q for test sandbox", sandbox.Namespace)
		if err := sandbox.Create(namespace); err != nil {
			f.lock.Unlock()
			t.Fatalf("error creating sandbox: %v", err)
		}

		f.sandboxes = append(f.sandboxes, sandbox)
		f.lock.Unlock()

		if f.destroySandboxes {
			defer sandbox.Destroy(namespace)
		}

		testFunc(t, sandbox)
	})
}
