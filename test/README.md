<!-- 
Copyright 2023 Google LLC

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
-->

# Test

The tests here are intended to test the recipes in this repo to make sure it workable and up-to-date.

PLEASE NOTE: All recipe tests are run periodically to ensure they are all passed. If a new recipe or changes to an existing recipe causes test failures, it will be reverted.

## Running tests locally

Make sure you have valid credentials for accessing GCP:

```
gcloud auth login
```

Set the project property in the core section by running:
```
gcloud config set project PROJECT_ID
```

Install jq by running:
```
sudo apt-get install jq
```

Make sure you are at the root directory of the repository.

```
cd gke-networking-recipes
```

Make sure to set ZONE and REGION environment variables before running tests. Resources will be deployed to the specified region and/or zone.
```
export ZONE=zone
export REGION=region
```

### To run a specific test
To run a specific test, run the setup.sh, run-test.sh, and cleanup.sh in order in the recipe directory.

```
./ingress/single-cluster/ingress-external-basic/setup.sh
./ingress/single-cluster/ingress-external-basic/run-test.sh
./ingress/single-cluster/ingress-external-basic/cleanup.sh
```

To cleanup a specific test separately, you can run its cleanup.sh.
```
./ingress/single-cluster/ingress-external-basic/cleanup.sh
```

### To run all tests
To run all tests, use the following make command:
```
make test
```

To cleanup all tests separately, use the following command from test/:
```
./test/cleanup-all.sh
```

## Adding a new recipe test

For a new recipe, in addition to its yaml file and REAME.md, it should also include a set of test files to make sure the recipe is functional and up-to-date. In the description section of the pull request, you should also provide the result of `make test` to show your test is passing and is not breaking other tests. See example in [output-example.txt](./test-example/output-example.txt).
If you are the first one adding tests to a component directory, make sure the directory is included in the testFilePaths in [recipe_test.go](./recipe_test.go)

A recipe directory should have the following layout:
```
gke-networking-recipes/
  ingress/
    single-cluster/
      ingress-external-basic/
        external-ingress.yaml
        README.md
        setup.sh     # Test file for setup resources
        run-test.sh  # Test file for validation
        cleanup.sh   # Test file for cleanup resources
      ...
```

Note that the files have to be named in the exact way to be picked up by the [test framework](recipe_test.go). If any of the test files is missing, it would be skipped by the framework.

You should validate your test passes by following instruction from `Running tests locally`. When creating a new test, you can utilize the helper functions defined in the [helper functions library](./helper.sh). You can find examples for each test file in the [test-example](./test-example/). In general, each test should contain at least one `check_http_status` call in its run-test.sh to validate the traffic.

For additional helper functions, please submit a feature request or raise a pull request with example. 
