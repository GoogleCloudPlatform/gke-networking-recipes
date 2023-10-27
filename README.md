# GKE Networking Recipes

This repository contains various use cases (aka Recipes) and examples of GKE Networking. For each of the use-cases there are full YAML examples that show how and when these GKE capabilities should be used.

Each recipes is a self-contained example. With a full tutorial for how to set it up and tear it down.

If you're not familiar with the basics of Kubernetes networking then check out [Cluster Networking](https://kubernetes.io/docs/concepts/cluster-administration/networking/) and [Service Networking](https://kubernetes.io/docs/concepts/services-networking/). These resources should give you some of the foundations behind Kubernetes networking.

GKE is a managed Kubernetes platform that provides a more opinionated and seamless experience. For more information on GKE networking, check out [network overview](https://cloud.google.com/kubernetes-engine/docs/concepts/network-overview), [Ingress](https://cloud.google.com/kubernetes-engine/docs/concepts/ingress), and [Service](https://cloud.google.com/kubernetes-engine/docs/how-to/exposing-apps) networking pages. Each of the following recipes demonstrate specific networking use-cases in GKE. [Setup your GKE environment](./cluster-setup.md) and try out some of these recipes in your own kitchen.

## Recipes

- Ingress
  - [Basic External Ingress](./ingress/single-cluster/ingress-external-basic) - Deploy host-based routing through an internet-facing HTTP load balancer
  - [Basic Internal Ingress](./ingress/single-cluster/ingress-internal-basic) - Deploy host-based routing through a private, internal HTTP load balancer
  - [Secure Ingress](./ingress/single-cluster/ingress-https) - Secure Ingress-hosted Services with HTTPS, Google-managed certificates, SSL policies, and HTTPS redirects.
  - [IAP Ingress](./ingress/single-cluster/ingress-iap) - GKE Ingress with Identity-Aware Proxy based authentication.
  - [CloudArmor Ingress](./ingress/single-cluster/ingress-cloudarmor) - GKE Ingress with Google CloudArmor policy protection.
  - [Nginx Ingress](./ingress/single-cluster/ingress-nginx) - Deploy an internet-facing HTTP load balancer with Nginx Ingress. 
  - [Custom default backend Ingress](./ingress/single-cluster/ingress-custom-default-backend) - GKE Ingress with custom default backend.
  - [Custom HTTP health check Ingress](./ingress/single-cluster/ingress-custom-http-health-check) - GKE Ingress with custom HTTP based health check.
  - [Custom gRPC health check Ingress](./ingress/single-cluster/ingress-custom-grpc-health-check) - GKE Ingress with custom gRPC based health check.
  - [Istio Ingress Gateway with multiple Backend Configs](./ingress/single-cluster/ingress-asm-multi-backendconfig) - Deploy ASM ingress gateway to run multiple different backends with different Backend Configs

- Multi-cluster Ingress
  - [Basic Multi-cluster Ingress](./ingress/multi-cluster/mci-basic) - Deploy applications across different clusters and different regions but retain a single global load balancer and public IP for global traffic management.
  - [Blue/Green Multi-cluster Ingress Cluster Migration](./ingress/multi-cluster/mci-blue-green-cluster) - Deploy applications across multiple clusters in the same region, leveraging a single global load balancer and public IP for global traffic management, to support seamless cluster upgrades without impacting client access.
  - (#Missing) [Blue/Green Multi-cluster Ingress App Migration](./ingress/multi-cluster/mci-blue-green-app) - Deploy applications across multiple clusters in the same region, leveraging a single global load balancer and public IP for global traffic management, to support seamless app upgrade without impacting client access.
  - [Multi-Cluster w/ FrontendConfig](./ingress/multi-cluster/mci-frontend-config) - Deploy applications across multiple clusters and use the [FrontendConfig CRD](https://cloud.google.com/kubernetes-engine/docs/how-to/ingress-features#configuring_ingress_features_through_frontendconfig_parameters) to configure HTTP to HTTPS redirect and customize the TLS configuration.
  - [Multi-Cluster E2E HTTPS](./ingress/multi-cluster/mci-https-e2e) - Deploy applications across different clusters with End to End HTTPS (Client -> (https) -> LoadBalancer -> (https) -> workload).
  - [Multi-Cluster Anthos Service Mesh E2E HTTPS](./ingress/multi-cluster/mci-asm-https-e2e) - Deploy applications across different clusters with Anthos Service Mesh and End to End HTTPS (Client -> (https) -> LoadBalancer -> (https) -> Istio Ingress Gateway -> (mTLS) -> Workload).

- Services
  - [Basic External LoadBalancer Service](./services/single-cluster/external-lb-service) - Deploy an internet-facing TCP/UDP network load balancer.
  - [Basic Internal LoadBalancer Service](./services/single-cluster/internal-lb-service) - Deploy an internal TCP/UDP load balancer.
  - [Basic Multi-Cluster Service](./services/multi-cluster/mcs-basic) - Deploy applications across multiple clusters. Applications is accessed across clusters via a VIP similar to accessing [ClusterIP Service](https://cloud.google.com/kubernetes-engine/docs/concepts/service#services_of_type_clusterip).

- Gateway
  - [Basic Multi-cluster Gateway](./gateway/multi-cluster/mcg-internal-basic) - Deploy an internal multi-cluster Gateway to load balance across applications across multiple clusters.
  - [Blue-Green Cluster Pattern with multi-cluster Gateway](./gateway/multi-cluster/mcg-internal-blue-green) - Deploy an internal multi-cluster Gateway to load balance across two versions of an application in different clusters, while utilizing traffic mirroring and traffic weighting to determine readiness and canary a new version of an application.
  - [gRPC LoadBalancing](./gateway/grpc) - Deploy gRPC application for internet facing and internal traffic.
  - [Single Cluster Global LoadBalancer](./gateway/single-cluster/global-l7-xlb) - Deploy an application and expose it with the Gateway API using the GatewayClass gke-l7-xlb.
  - [Single Cluster Global LoadBalancer HTTPS between the GCLB and the Backend app](./gateway/single-cluster/global-l7-xlb-https-backend) - Deploy an app behind a Global LoadBalancer with the GatewayClass gke-l7-xlb and encrypt traffic between the LB and the backend app using HAProxy.
  - [Single Cluster Regional Internal LoadBalancer](./gateway/single-cluster/regional-l7-ilb) - Deploy an application and expose it with the Gateway API using the GatewayClass gke-l7-rilb.

### Testing the recipes

See [test/README.md](test/README.md) for instructions on how to run the examples recipes against your project.

### Contributions

Do you have a GKE networking recipe that would be useful for others? [Contribute it](CONTRIBUTING.md) and help build the shared knowledge of the GKE community!