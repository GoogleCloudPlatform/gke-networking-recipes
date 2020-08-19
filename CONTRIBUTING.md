# How to Contribute

We'd love to accept your patches and contributions to this project. There are just a few small guidelines you need to follow.

## Format and Structure Guidelines

The goal for GKE Networking Recipes is to provide a bite-sized, easy to consume, and consistent set of self-contained examples that can be used to accomplish realistic networking use-cases on GKE. Consistency in format and structure of these "recipes" will improve understanding and also aid in the long-term maintenance of this repository. Please follow these guidelines where it makes sense and deviate where it does not, but use your judgement to ensure that they are reasonably consistent while still highlighting your special use-case!

### Recipe guidelines

- Each recipe should be a self-contained example that accomplishes a realistic use-case or set of related use-cases. 
- Each recipe should have its own folder that includes all of the deployment YAML necessary to achieve the use-case in addition to its README.
- The resource manifests should be stored in a single YAML file so that it can be easily copied, pasted, and deployed with a single command. Exceptions include multiple deployment steps (like v1 and v2 of an app) or multiple clusters where different manifests are deployed to each.
- Each recipe should use the [whereami sample application](https://github.com/GoogleCloudPlatform/kubernetes-engine-samples/tree/master/whereami) wherever possible to demonstrate the use-case. There may be use-cases that depend on specific application functionality so it is fine to diverge in these instances.
- Recipes should rely on the shared [GKE cluster setup](,/cluster-setup.md) steps instead of instructing how to deploy the cluster or environment. Each recipe should focus on just the use-case without repeating any boilerplate setup. For special cases where a unique environment or more than one cluster is required, feel free to include these steps in the recipe.
- There should be clear ownership of a recipe. Each recipe has one owner. If you contributed it then you own it until someone else has agreed to be the owner. If functionality changes and your recipe is no longer valid or no longer makes sense, it is your responsibility to update over time.
- Each recipe should be listed as a bullet point with a brief description on the [primary README page](./README.md)


### README guidelines
Each recipe's README should consist of the following sections. In general the README should be concise and should not try to replicate the docs or be a solutions guide. Keep it bite sized.

- Summary
	- A brief description of what this recipe accomplishes
	- Any references to specific GKE features or GCP load balancers should be appropriately linked
	- The use-cases that this recipe accomplishes should be listed
	- A diagram [of this format](https://docs.google.com/presentation/d/1Wngda7LN4GcMpASvdnG-laLUDOt3hzmPeUuVvMdSXA0/edit?usp=sharing) should be used to describe the networking flow, example, or architecture wherever it makes sense. Images should go into the [`/images`](./images) folder.
- Network manifests
	- This section describes the primary capabilities and configuration format for the features that are highlighted in this recipe
	- This section should only focus on the networking-related manifests but not show or describe all the manifests (such as app deployment)
- Try it out
	- This section should describe in a few steps how to deploy the networking manifests to achieve the use-case
	- Do not try and recreate an entire tutorial. Try to demonstrate this in as few steps as necessary and put most of the description and detail in the Network Manifests section
	- Demonstrate that the use-case works and display the output that validates it (whether that be a succesful ping or a specific expected response)
- Example remarks
  - Use this section if it's necessary to add closing comments or add any detail to the example for explanation.
- Cleanup
  - Everything needed to delete the resources created in this recipe

## Recipe Ownership

| Recipe  | Owner |
| ------------- | ------------- |
| [Basic External Ingress](/external-ingress-basic)  | [@mark-church](https://github.com/mark-church)  |
| [Basic Internal Ingress](/internal-ingress-basic)  |  [@legranda](https://github.com/aurelienlegrand)  |
| [External LoadBalancer Service](/external-lb-service)  |   |
| [Internal LoadBalancer Service](/internal-lb-service)  |   |
| [Custom Ingress Health Check](/ingress-custom-http-health-check)  |   |
| [Ingress gRPC Health Check](/ingress-custom-grpc-health-check)  | [@rramkumar1](https://github.com/rramkumar1)  |
| [Basic Multi-Cluster Ingress](/multi-cluster-external-ingress)  | [@mark-church](https://github.com/mark-church)  |
| [Multi-Cluster Ingress Blue-Green App Migration](/multi-cluster-blue-green-app)  |   |
| [Multi-Cluster Ingress Blue-Green Cluster Migration](/multi-cluster-blue-green-cluster)  |   |



## Contributor License Agreement

Contributions to this project must be accompanied by a Contributor License
Agreement. You (or your employer) retain the copyright to your contribution,
this simply gives us permission to use and redistribute your contributions as
part of the project. Head over to <https://cla.developers.google.com/> to see
your current agreements on file or to sign a new one.

You generally only need to submit a CLA once, so if you've already submitted one
(even if it was for a different project), you probably don't need to do it
again.

## Code reviews

All submissions, including submissions by project members, require review. We
use GitHub pull requests for this purpose. Consult
[GitHub Help](https://help.github.com/articles/about-pull-requests/) for more
information on using pull requests.