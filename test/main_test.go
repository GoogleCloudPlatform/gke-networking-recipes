// Copyright 2019 Google LLC
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
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/GoogleCloudPlatform/gke-networking-recipes/test/utils"
	"github.com/GoogleCloudPlatform/k8s-cloud-provider/pkg/cloud"
	"k8s.io/client-go/tools/clientcmd"
	backendconfigclient "k8s.io/ingress-gce/pkg/backendconfig/client/clientset/versioned"
	frontendconfigclient "k8s.io/ingress-gce/pkg/frontendconfig/client/clientset/versioned"
	"k8s.io/klog/v2"
	ctrlClient "sigs.k8s.io/controller-runtime/pkg/client"
)

var (
	flags struct {
		kubeconfig      string
		testProjectID   string
		testClusterName string
		location        string
		numOfNodes      int
		// Test infrastructure flags.
		boskosResourceType string
		inProw             bool
		deleteCluster      bool
	}
	Framework struct {
		Client               ctrlClient.Client
		BackendConfigClient  *backendconfigclient.Clientset
		FrontendConfigClient *frontendconfigclient.Clientset
		Cloud                cloud.Cloud
	}
)

func init() {
	flag.StringVar(&flags.kubeconfig, "kubeconfig", "", "path to the .kube config file. This will default to $HOME/.kube/config if unset.")
	flag.StringVar(&flags.boskosResourceType, "boskos-resource-type", "gke-internal-project", "name of the boskos resource type to reserve")
	flag.BoolVar(&flags.inProw, "run-in-prow", false, "is the test running in PROW")
	flag.StringVar(&flags.testProjectID, "test-project-id", "", "Project ID of the test cluster")
	flag.StringVar(&flags.testClusterName, "cluster-name", "", "Name of the test cluster")
	flag.StringVar(&flags.location, "location", "", "Location of the test cluster")
	flag.IntVar(&flags.numOfNodes, "num-nodes", 3, "The number of nodes to be created in each of the cluster's zones")
	flag.BoolVar(&flags.deleteCluster, "delete-cluster", false, "if the cluster is deleted after test runs")
}

func TestMain(m *testing.M) {
	flag.Parse()
	klog.Infof("Flags: %+v", flags)

	if flags.kubeconfig == "" {
		if home := os.Getenv("HOME"); home != "" {
			flags.kubeconfig = filepath.Join(home, ".kube", "config")
		} else {
			klog.Fatalf("kubeconfig path required but not provided")
		}
	}

	if flags.testClusterName == "" {
		randSuffix := randSeq(6)
		flags.testClusterName = "gke-networking-recipes-" + randSuffix
	}

	if flags.location == "" {
		fmt.Fprintln(os.Stderr, "--location must be set to run the test")
		os.Exit(1)
	}

	project := flags.testProjectID
	// If running in Prow, then acquire and set up a project through Boskos.
	if flags.inProw {
		ph, err := utils.NewProjectHolder()
		if err != nil {
			klog.Fatalf("NewProjectHolder()=%v, want nil", err)
		}
		project = ph.AcquireOrDie(flags.boskosResourceType)
		defer func() {
			ph.Release()
		}()

		if _, ok := os.LookupEnv("USER"); !ok {
			if err := os.Setenv("USER", "prow"); err != nil {
				klog.Fatalf("failed to set user in prow to prow: %v", err)
			}
		}
	}

	output, _ := exec.Command("gcloud", "config", "get-value", "project").CombinedOutput()
	oldProject := strings.TrimSpace(string(output))
	klog.Infof("Using project %s for testing. Restore to existing project %s after testing.", project, oldProject)

	if err := setEnvProject(project); err != nil {
		klog.Fatalf("failed to set project environment to %q: %v", project, err)
	}

	// After the test, reset the project
	defer func() {
		if err := setEnvProject(oldProject); err != nil {
			klog.Errorf("failed to set project environment to %s: %v", oldProject, err)
		}
	}()

	klog.Infof("setupCluster(%q, %q, %d)", flags.location, flags.testClusterName, flags.numOfNodes)
	if err := setupCluster(flags.location, flags.testClusterName, flags.numOfNodes); err != nil {
		klog.Fatalf("setupCluster(%q, %q, %d) = %v", flags.location, flags.testClusterName, flags.numOfNodes, err)
	}
	klog.Infof("getCredential(%q, %q)", flags.location, flags.testClusterName)
	if err := getCredential(flags.location, flags.testClusterName); err != nil {
		klog.Fatalf("getCredential(%q, %q) = %v", flags.location, flags.testClusterName, err)
	}
	if flags.deleteCluster {
		defer func() {
			klog.Infof("deleteCluster(%q, %q)", flags.location, flags.testClusterName)
			if err := deleteCluster(flags.location, flags.testClusterName); err != nil {
				klog.Errorf("deleteCluster(%q, %q) = %v", flags.location, flags.testClusterName, err)
			}
		}()
	}

	klog.Infof("Using kubeconfig %q", flags.kubeconfig)
	kubeconfig, err := clientcmd.BuildConfigFromFlags("", flags.kubeconfig)
	if err != nil {
		klog.Fatalf("Error creating kubernetes clients from %q: %v", flags.kubeconfig, err)
	}
	client, err := ctrlClient.New(kubeconfig, ctrlClient.Options{})
	if err != nil {
		klog.Errorf("Failed to create kubernetes client: %v", err)
	}
	Framework.Client = client
	Framework.BackendConfigClient = backendconfigclient.NewForConfigOrDie(kubeconfig)
	Framework.FrontendConfigClient = frontendconfigclient.NewForConfigOrDie(kubeconfig)

	Framework.Cloud, err = newCloud(project)
	if err != nil {
		klog.Fatalf("Error creating compute client for project %q: %v", project, err)
	}

	m.Run()
}

func TestHelloWorld(t *testing.T) {
	klog.Info("Hello world")
}
