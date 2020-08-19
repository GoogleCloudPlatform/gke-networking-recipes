# GKE Networking Recipes

This repository contains various use cases and examples of GKE Networking. For each of the use-cases there are full YAML examples that show how and when these GKE capabilities should be used.

If you're not familiar with the basics of Kubernetes networking then check out [cluster networking](https://kubernetes.io/docs/concepts/cluster-administration/networking/) and [service networking](https://kubernetes.io/docs/concepts/services-networking/). These resources should give you some of the foundations behind Kubernetes networking.

GKE is a managed Kubernetes platform that provides a more opinionated and seamless experience. For more information on GKE networking, check out [network overview](https://cloud.google.com/kubernetes-engine/docs/concepts/network-overview), [Ingress](https://cloud.google.com/kubernetes-engine/docs/concepts/ingress), and [Service](https://cloud.google.com/kubernetes-engine/docs/how-to/exposing-apps) networking pages.Each of the following recipes demonstrate specific networking use-cases in GKE. [Setup your GKE environment](./cluster-setup.md) and try out some of these recipes in your own kitchen.

## Recipes

- [Basic External Ingress](./ingress/external-ingress-basic) - Deploy host-based routing through an internet-facing HTTP load balancer
- [Basic Internal Ingress](./ingress/internal-ingress-basic) - Deploy host-based routing through a private, internal HTTP load balancer



### Contributions

Do you have a GKE networking recipe that would be useful for others? [Contribute it](CONTRIBUTING.md) and help build the shared knowledge of the GKE community!

