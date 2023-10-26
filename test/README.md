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

## Running the test locally

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

To run all tests, use the following make command:
```
make test
```

To cleanup all tests separately, use the following command from test/:
```
./test/cleanup_all.sh
```