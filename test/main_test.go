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
	"k8s.io/client-go/tools/clientcmd"
	"k8s.io/klog/v2"
)

var (
	flags struct {
		kubeconfig      string
		pkgDir          string
		testProjectID   string
		testNetworkName string
		testSubnetName  string
		testClusterName string
		zone            string
		numOfNodes      int
		// Test infrastructure flags.
		boskosResourceType string
		inProw             bool
		deleteCluster      bool
		destroySandboxes   bool
	}
	framework *utils.Framework
)

func init() {
	flag.StringVar(&flags.kubeconfig, "kubeconfig", "", "path to the .kube config file. This will default to $HOME/.kube/config if unset.")
	flag.StringVar(&flags.boskosResourceType, "boskos-resource-type", "gke-internal-project", "name of the boskos resource type to reserve")
	flag.BoolVar(&flags.inProw, "run-in-prow", false, "is the test running in PROW")
	flag.StringVar(&flags.pkgDir, "pkg-dir", "", "path from $GOPATH to repo. This will default to src/github.com/GoogleCloudPlatform/gke-networking-recipes if unset")
	flag.StringVar(&flags.testProjectID, "test-project-id", "", "Project ID of the test cluster")
	flag.StringVar(&flags.testNetworkName, "network-name", "", "Name of the test network. This will default to gke-net-recipes-test if unset.")
	flag.StringVar(&flags.testSubnetName, "subnet-name", "", "Name of the test subnet. This will default to gke-net-recipes-test if unset.")
	flag.StringVar(&flags.testClusterName, "cluster-name", "", "Name of the test cluster. This will default to gke-net-recipes-test if unset.")
	flag.StringVar(&flags.zone, "zone", "", "Zone of the test cluster")
	flag.IntVar(&flags.numOfNodes, "num-nodes", 3, "The number of nodes to be created in each of the cluster's zones")
	flag.BoolVar(&flags.deleteCluster, "delete-cluster", false, "if the cluster is deleted after test runs")
	flag.BoolVar(&flags.destroySandboxes, "destroySandboxes", true, "set to false to leave sandboxed resources for debugging")
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

	if flags.zone == "" {
		fmt.Fprintln(os.Stderr, "--zone must be set to run the test")
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
				klog.Fatalf("failed to set user in prow to prow: %v, want nil", err)
			}
		}
	}

	output, err := exec.Command("gcloud", "config", "get-value", "project").CombinedOutput()
	if err != nil {
		klog.Fatalf("failed to get gcloud project: %q: %v, want nil", string(output), err)
	}
	oldProject := strings.TrimSpace(string(output))
	klog.Infof("Using project %s for testing. Restore to existing project %s after testing.", project, oldProject)

	if err := setEnvProject(project); err != nil {
		klog.Fatalf("setEnvProject(%q) failed: %v, want nil", project, err)
	}

	// After the test, reset the project
	defer func() {
		if err := setEnvProject(oldProject); err != nil {
			klog.Errorf("setEnvProject(%q) failed: %v, want nil", oldProject, err)
		}
	}()

	klog.Infof("Using kubeconfig %q", flags.kubeconfig)
	kubeconfig, err := clientcmd.BuildConfigFromFlags("", flags.kubeconfig)
	if err != nil {
		klog.Fatalf("BuildConfigFromFlags(%q) = %v, want nil", flags.kubeconfig, err)
	}

	framework = utils.NewFramework(kubeconfig, utils.Options{
		Project:          flags.testProjectID,
		Zone:             flags.zone,
		NetworkName:      flags.testNetworkName,
		SubnetName:       flags.testSubnetName,
		DestroySandboxes: flags.destroySandboxes,
	})

	clusterConfig := utils.ClusterConfig{
		Name:        flags.testClusterName,
		Zone:        flags.zone,
		NumOfNodes:  flags.numOfNodes,
		NetworkName: framework.Network.Name,
		SubnetName:  framework.Subnet.Name,
	}
	klog.Infof("EnsureCluster(%+v)", clusterConfig)
	err = utils.EnsureCluster(clusterConfig)
	if err != nil {
		klog.Fatalf("EnsureCluster(%+v) = %v, want nil", clusterConfig, err)
	}
	klog.Infof("GetCredentials(%+v)", clusterConfig)
	if err := utils.GetCredentials(clusterConfig); err != nil {
		klog.Fatalf("GetCredentials(%+v) = %v, want nil", clusterConfig, err)
	}
	if flags.deleteCluster {
		defer func() {
			klog.Infof("DeleteCluster(%+v)", clusterConfig)
			if err := utils.DeleteCluster(clusterConfig); err != nil {
				klog.Errorf("DeleteCluster(%+v) = %v, want nil", clusterConfig, err)
			}
		}()
	}

	m.Run()
}

func TestHelloWorld(t *testing.T) {
	klog.Info("Hello world")
}
