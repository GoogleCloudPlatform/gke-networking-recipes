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

package test

import (
	"bytes"
	"context"
	"fmt"
	"math/rand"
	"os"
	"os/exec"
	"strconv"
	"time"

	"github.com/GoogleCloudPlatform/k8s-cloud-provider/pkg/cloud"
	"golang.org/x/oauth2/google"
	alpha "google.golang.org/api/compute/v0.alpha"
	beta "google.golang.org/api/compute/v0.beta"
	compute "google.golang.org/api/compute/v1"
	"k8s.io/apimachinery/pkg/util/wait"
	"k8s.io/client-go/util/retry"
	"k8s.io/klog/v2"
	boskosclient "sigs.k8s.io/boskos/client"
	"sigs.k8s.io/boskos/common"
)

var boskos, _ = boskosclient.NewClient(os.Getenv("JOB_NAME"), "http://boskos", "", "")

// getBoskosProject retries acquiring a boskos project until success or timeout.
func getBoskosProject(resourceType string) *common.Resource {
	var project *common.Resource
	err := retry.OnError(
		wait.Backoff{
			Duration: time.Second,
			Factor:   1.0,
			Steps:    10,
		},
		func(err error) bool { return true },
		func() error {
			project, err := boskos.Acquire(resourceType, "free", "busy")
			if err != nil {
				return fmt.Errorf("boskos failed to acquire project: %w", err)
			}
			if project != nil {
				return fmt.Errorf("boskos does not have a free %s at the moment", resourceType)
			}
			return nil
		},
	)
	if err != nil {
		klog.Fatalf("timed out trying to acquire boskos project")
	}
	return project
}

func setupProwConfig(resourceType string) string {
	// Try to get a Boskos project
	klog.Info("Running in PROW")
	klog.Info("Fetching a Boskos loaned project")

	p := getBoskosProject(resourceType)
	project := p.Name

	go func(c *boskosclient.Client) {
		for range time.Tick(time.Minute * 5) {
			if err := c.UpdateOne(p.Name, "busy", nil); err != nil {
				klog.Warningf("[Boskos] Update %s failed with %v", p.Name, err)
			}
		}
	}(boskos)

	return project
}

func setEnvProject(project string) error {
	if out, err := exec.Command("gcloud", "config", "set", "project", project).CombinedOutput(); err != nil {
		return fmt.Errorf("failed to set gcloud project to %s: %s, err: %w", project, out, err)
	}

	return os.Setenv("PROJECT", project)
}

func setupCluster(location, clusterName string, numOfNodes int) error {
	params := []string{
		"container",
		"clusters",
		"describe",
		clusterName,
		"--zone", location,
	}
	out, err := exec.Command("gcloud", params...).CombinedOutput()
	if err != nil {
		klog.Infof("Cluster %s does not exist, creating instead.", clusterName)
		return createCluster(location, clusterName, numOfNodes)
	}

	pattern := "currentNodeCount: "
	startIndex := bytes.Index(out, []byte(pattern)) + len(pattern)       // The index immediately after the pattern.
	endIndex := startIndex + bytes.Index(out[startIndex:], []byte("\n")) // The index after the pattern and before new line.
	if startIndex == -1 || endIndex == -1 {
		klog.Infof("Cannot find current node count. Delete and recreate cluster.")
		return deleteAndCreateCluster(location, clusterName, numOfNodes)
	}

	gotNumOfNodes, err := strconv.Atoi(string(out[startIndex:endIndex]))
	if err != nil || gotNumOfNodes != numOfNodes {
		klog.Infof("Got cluster with %d nodes, expect %d. Delete and recreate cluster %s in %s.", gotNumOfNodes, numOfNodes, clusterName, location)
		return deleteAndCreateCluster(location, clusterName, numOfNodes)
	}
	klog.Infof("Use existing cluster %s in zone %s with %d nodes", clusterName, location, numOfNodes)
	return nil
}

func createCluster(location, clusterName string, numOfNodes int) error {
	klog.Infof("Creating cluster %s in %s, numOfNodes=%d", clusterName, location, numOfNodes)
	params := []string{
		"container",
		"clusters",
		"create",
		clusterName,
		"--zone", location,
		"--num-nodes", strconv.Itoa(numOfNodes),
	}
	if out, err := exec.Command("gcloud", params...).CombinedOutput(); err != nil {
		return fmt.Errorf("failed creating cluster: %s, err: %v", out, err)
	}
	return nil
}

func deleteCluster(location, clusterName string) error {
	klog.Infof("Deleting cluster %s in %s", clusterName, location)
	params := []string{
		"container",
		"clusters",
		"delete",
		clusterName,
		"--zone",
		location,
		"--quiet",
	}
	if out, err := exec.Command("gcloud", params...).CombinedOutput(); err != nil {
		return fmt.Errorf("failed deleting cluster: %s, err: %v", out, err)
	}
	return nil
}

func deleteAndCreateCluster(location, clusterName string, numOfNodes int) error {
	if err := deleteCluster(location, clusterName); err != nil {
		return fmt.Errorf("failed delete and create cluster: %s, err: %v", clusterName, err)
	}
	if err := createCluster(location, clusterName, numOfNodes); err != nil {
		return fmt.Errorf("failed delete and create cluster: %s, err: %v", clusterName, err)
	}
	return nil
}

func getCredential(location, clusterName string) error {
	params := []string{
		"container",
		"clusters",
		"get-credentials",
		clusterName,
		"--zone",
		location,
	}
	if out, err := exec.Command("gcloud", params...).CombinedOutput(); err != nil {
		return fmt.Errorf("failed setting kubeconfig: %s, err: %v", out, err)
	}
	return nil
}

func newCloud(project string) (cloud.Cloud, error) {
	ctx := context.Background()
	client, err := google.DefaultClient(ctx, compute.ComputeScope)
	if err != nil {
		return nil, err
	}

	alpha, err := alpha.New(client)
	if err != nil {
		return nil, err
	}
	beta, err := beta.New(client)
	if err != nil {
		return nil, err
	}
	ga, err := compute.New(client)
	if err != nil {
		return nil, err
	}

	svc := &cloud.Service{
		GA:            ga,
		Alpha:         alpha,
		Beta:          beta,
		ProjectRouter: &cloud.SingleProjectRouter{ID: project},
		RateLimiter:   &cloud.NopRateLimiter{},
	}

	theCloud := cloud.NewGCE(svc)
	return theCloud, nil
}

func randSeq(n int) string {
	letterBytes := "0123456789abcdef"
	b := make([]byte, n)
	for i := range b {
		b[i] = letterBytes[rand.Intn(len(letterBytes))]
	}
	return string(b)
}