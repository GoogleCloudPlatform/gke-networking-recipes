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
	"os"
	"os/exec"
	"path"
	"testing"
)

var testFilePaths = []string{
	"ingress/single-cluster/",
}

func TestRecipes(t *testing.T) {
	t.Parallel()

	if out, err := exec.Command("bash", "./test/setup.sh").CombinedOutput(); err != nil {
		t.Fatalf("Failed to create test setup: %s: %v", out, err)
	}
	t.Cleanup(func() {
		if out, err := exec.Command("bash", "./test/cleanup.sh").CombinedOutput(); err != nil {
			t.Fatalf("Failed to delete test setup: %s: %v", out, err)
		}
	})

	for _, fp := range testFilePaths {
		dirs, err := os.ReadDir(fp)
		if err != nil {
			t.Fatalf("Failed to open directory %s: %v", fp, err)
		}

		for _, dir := range dirs {
			dir := dir
			t.Run(dir.Name(), func(t *testing.T) {
				t.Parallel()
				f := path.Join(fp, dir.Name(), "run-test.sh")
				out, err := exec.Command("bash", f).CombinedOutput()
				if err != nil {
					t.Errorf("Test %s failed: %s, err: %v", dir.Name(), out, err)
				}
			})
		}
	}
}
