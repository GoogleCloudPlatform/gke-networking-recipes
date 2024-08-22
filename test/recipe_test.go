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
	"fmt"
	"io/fs"
	"os"
	"os/exec"
	"path"
	"strings"
	"testing"
	"time"
)

var testFilePaths = []string{
	"ingress/single-cluster/",
	"authz/",
}

func TestRecipe(t *testing.T) {
	for _, fp := range testFilePaths {
		fileNames, err := os.ReadDir(fp)
		if err != nil {
			t.Fatalf("os.ReadDir(%q) = %v", fp, err)
		}
		runRecipeTests(t, fp, fileNames)
	}
}

// runRecipeTests iterates each recipe file, and run its test if it is a directory.
func runRecipeTests(t *testing.T, parentPath string, fileNames []fs.DirEntry) {
	for i, fileName := range fileNames {
		i := i
		fileName := fileName
		t.Run(fileName.Name(), func(t *testing.T) {
			t.Parallel()
			// Pause 30*i seconds
			time.Sleep(time.Duration(i*30) * time.Second)
			path := path.Join(parentPath, fileName.Name())
			if err := validateDir(path); err != nil {
				t.Skipf("Skipping test %q: validateDir(%q) = %v", path, path, err)
			}
			runRecipeTest(t, path)
		})
	}
}

// runRecipeTest runs the testing scripts for a specific recipe.
// Test will be skipped if setup.sh, run-test.sh, or cleanup.sh does not exist
// in the target directory.
// If a test fails, its cleanup needs to be run manually. See directions in
// test/README.md.
func runRecipeTest(t *testing.T, recipeDir string) {
	var paths []string
	for _, file := range []string{"setup.sh", "run-test.sh", "cleanup.sh"} {
		path := path.Join(recipeDir, file)
		_, err := os.Stat(path)
		if err != nil && !strings.Contains(path, "authz") {
			t.Logf("stat(%q) = %v", path, err)
			t.Skipf("Skipping test %q: %q doesn't exist", recipeDir, path)
		}
		if err == nil {
			paths = append(paths, path)
		}
	}

	for _, path := range paths {
		out, err := exec.Command("bash", path).CombinedOutput()
		if err != nil {
			// Fail now because we shouldn't continue testing if any step fails.
			t.Fatalf("Test %s failed when running %q: %q, err: %v", recipeDir, path, out, err)
		}
	}
}

// validateDir validates if the given path corresponds to a directory.
func validateDir(path string) error {
	d, err := os.Stat(path)
	if err != nil {
		return fmt.Errorf("stat(%q) failed: %w", path, err)
	}
	if !d.IsDir() {
		return fmt.Errorf("%q is not a directory", path)
	}
	return nil
}
