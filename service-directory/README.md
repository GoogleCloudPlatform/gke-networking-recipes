# Service Directory GKE Integration Recipes

Service Directory for GKE is a cloud-hosted controller for GKE Clusters that
sync Services to Service Directory.

This repository contains examples of the various Kubernetes Service types. For
each of the types, there are full YAML examples that show how each Service type
syncs to Service Directory.

### Relevant Documentation

*   [Service Directory Concepts](https://cloud.google.com/service-directory/docs/concepts)
*   [Service Directory with GKE Overview](https://cloud.google.com/service-directory/docs/sd-gke-overview)
*   [Configuring Service Directory for GKE](https://cloud.google.com/service-directory/docs/configuring-sd-for-gke)

### Recipes

*  [Internal LoadBalancer](./internal-lb-service)
*  [ClusterIP](./cluster-ip-service)
*  [Headless](./headless-service)
*  [NodePort](./nodeport-service)
