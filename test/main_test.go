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
	"os"
	"os/exec"
	"strings"
	"testing"

	"github.com/GoogleCloudPlatform/gke-networking-recipes/test/utils"
	"k8s.io/klog/v2"
)

var (
	flags struct {
		boskosResourceType string
		inProw             bool
	}
)

func init() {
	flag.StringVar(&flags.boskosResourceType, "boskos-resource-type", "gke-internal-project", "name of the boskos resource type to reserve")
	flag.BoolVar(&flags.inProw, "run-in-prow", false, "is the test running in PROW")
}

func TestMain(m *testing.M) {
	flag.Parse()
	klog.Infof("Flags: %+v", flags)

	// If running in Prow, then acquire and set up a project through Boskos.
	if flags.inProw {
		ph, err := utils.NewProjectHolder()
		if err != nil {
			klog.Fatalf("NewProjectHolder()=%v, want nil", err)
		}
		project := ph.AcquireOrDie(flags.boskosResourceType)
		defer func() {
			out, err := exec.Command("bash", "test/cleanup-all.sh").CombinedOutput()
			if err != nil {
				// Fail now because we shouldn't continue testing if any step fails.
				klog.Errorf("failed to run ./test/cleanup-all.sh: %q, err: %v", out, err)
			}
			ph.Release()
		}()

		if _, ok := os.LookupEnv("USER"); !ok {
			if err := os.Setenv("USER", "prow"); err != nil {
				klog.Fatalf("failed to set user in prow to prow: %v, want nil", err)
			}
		}

		output, err := exec.Command("gcloud", "config", "get-value", "project").CombinedOutput()
		if err != nil {
			klog.Fatalf("failed to get gcloud project: %q: %v, want nil", string(output), err)
		}
		oldProject := strings.TrimSpace(string(output))
		klog.Infof("Using project %s for testing. Restore to existing project %s after testing.", project, oldProject)

		if err := utils.SetEnvProject(project); err != nil {
			klog.Fatalf("SetEnvProject(%q) failed: %v, want nil", project, err)
		}

		// After the test, reset the project
		defer func() {
			if err := utils.SetEnvProject(oldProject); err != nil {
				klog.Errorf("SetEnvProject(%q) failed: %v, want nil", oldProject, err)
			}
		}()
	}

	m.Run()
}
