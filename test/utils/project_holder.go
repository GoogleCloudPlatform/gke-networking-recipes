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
	"fmt"
	"os"
	"time"

	"k8s.io/apimachinery/pkg/util/wait"
	"k8s.io/client-go/util/retry"
	"k8s.io/klog/v2"
	boskosclient "sigs.k8s.io/boskos/client"
	"sigs.k8s.io/boskos/common"
)

const (
	retryDuration = 10 * time.Second
	retryFactor   = 1.0
	retryStep     = 30

	// How often we send update to boskos client to refresh the resource.
	updateInterval = 5 * time.Minute
)

type ProjectHolder struct {
	c *boskosclient.Client
	// quit channel signals when we need to stop refresh the resource and release the boskos project.
	quit chan struct{}
	// Name of the project to use.
	project string
}

func NewProjectHolder() (*ProjectHolder, error) {
	jobName := os.Getenv("JOB_NAME")
	if jobName == "" {
		return nil, fmt.Errorf("JOB_NAME is required but not provided")
	}
	c, err := boskosclient.NewClient(jobName, "http://boskos", "", "")
	if err != nil {
		return nil, err
	}
	return &ProjectHolder{
		c:    c,
		quit: make(chan struct{}),
	}, nil
}

// AcquireOrDie tries to get a boskso project. If succeeded, it spawns a
// goroutine to refresh it and returns the name of the project to use.
// If failed, it will terminate.
func (ph *ProjectHolder) AcquireOrDie(resourceType string) string {
	// Try to get a Boskos project
	klog.Infof("Running in Prow, getting project resourceType = %q", resourceType)

	p := ph.getBoskosProjectOrDie(resourceType)
	ph.project = p.Name
	go ph.refresh()

	return p.Name
}

// Release stops the refresh goroutine, and releases the boskso project.
func (ph *ProjectHolder) Release() {
	ph.quit <- struct{}{}

	// Wait until project cleanup is finished.
	<-ph.quit
}

// Periodically refresh the resource to avoid the resource being cleaned
// up accidentally.
// Boskos Reaper component looks for resources that are owned but not
// updated for a period of time, and resets stale resources to dirty state,
// and Boskos Janitor component cleans up all dirty resources.
func (ph *ProjectHolder) refresh() {
	for {
		select {
		case <-time.Tick(updateInterval):
			if err := ph.c.UpdateOne(ph.project, common.Busy, nil); err != nil {
				klog.Warningf("[Boskos] Update %s failed with %v", ph.project, err)
			}
		case <-ph.quit:
			if err := ph.c.ReleaseOne(ph.project, common.Dirty); err != nil {
				klog.Warningf("[Boskos] ReleaseOne %s failed with %v", ph.project, err)
			}
			ph.quit <- struct{}{}
			return
		}
	}
}

// getBoskosProjectOrDie retries acquiring a boskos project until success or timeout and terminate.
func (ph *ProjectHolder) getBoskosProjectOrDie(resourceType string) *common.Resource {
	var project *common.Resource
	err := retry.OnError(
		wait.Backoff{
			Duration: retryDuration,
			Factor:   retryFactor,
			Steps:    retryStep,
		},
		func(err error) bool { return err != nil },
		func() error {
			klog.Infof("Trying to acquire boskos project of type %s...", resourceType)
			var err error
			project, err = ph.c.Acquire(resourceType, common.Free, common.Busy)
			if err != nil {
				return err
			}
			return nil
		},
	)
	if err != nil || project == nil {
		klog.Fatalf("Error trying to acquire boskos project: %v", err)
	}
	return project
}
