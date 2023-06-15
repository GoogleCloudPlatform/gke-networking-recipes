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

You will need to set the project to run the test locally:

```
export PROJECT_ID=<your-project>
```

To specify the location to create the test cluster, you will need to set the environment varible, it will be `us-central1-c` by default.

```
export LOCATION=<your-location>
```

Then run to start the test or select a set of tests to run:

```
make test TEST_TO_RUN=<regex to filter test>
```
