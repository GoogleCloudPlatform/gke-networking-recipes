# GKE Ingress with custom HTTP health check

Following recipe provides a walk-through for setting up [GKE Ingress](https://cloud.google.com/kubernetes-engine/docs/concepts/ingress)
with custom HTTP health check.

GKE Ingresses use proxy-based [Google Cloud HTTP(s) Load Balancers](https://cloud.google.com/load-balancing/docs/https)
that can serve multiple backend services (Kubernetes services in GKE case). Each of those backend services
must reference [Google Cloud health check](https://cloud.google.com/load-balancing/docs/health-check-concepts).
GKE creates those health checks with parameters that are either explicitly configured, inferred or
have default values.

It is recommended practice to configure health check parameters explicitly for GKE Ingress backend services.

## Use cases

* Explicitly configure health check parameters for your service

## Relevant documentation

* [GKE Ingress overview](https://cloud.google.com/kubernetes-engine/docs/concepts/ingress)
* [GKE Ingress health checks](https://cloud.google.com/kubernetes-engine/docs/concepts/ingress#health_checks)
* [Custom health check configuration](https://cloud.google.com/kubernetes-engine/docs/how-to/ingress-features#direct_health)

---

![iap-ingress](../../images/healthcheck-ingress.png)

GKE creates [Google Cloud health check](https://cloud.google.com/load-balancing/docs/health-check-concepts)
for each Ingress backend service in one of a following ways:

* If service references [BackendConfig CRD](https://github.com/kubernetes/ingress-gce/tree/master/pkg/apis/backendconfig)
with `healthCheck` information, then GKE uses that to create the health check.

Otherwise:

* If service Pods use Pod template with a container that has readiness probe, GKE can infer some or
all of the parameters form that probe for health check configuration.
Check [Parameters from a readiness probe](https://cloud.google.com/kubernetes-engine/docs/concepts/ingress#interpreted_hc)
for details.

* If service Pods use Pod template with a container that **does not** have a container with a readiness
probe whose attribute can be interpreted as health check parameters, the [default values](https://cloud.google.com/kubernetes-engine/docs/concepts/ingress#def_inf_hc)
are used.

**NOTE**: keep in mind differences in destination port when configuring `healthCheck` parameters in
`BackendConfig` object for services that use [Container Native Load Balancing](https://cloud.google.com/kubernetes-engine/docs/how-to/container-native-load-balancing).

* When using container native load balancing, port should match `containerPort` of a serving Pod

* For backends based on instance groups, port should match `nodePort` exposed by the service

## Walk-through

Prerequisites:

* GKE cluster up and running *(check [Prerequisite: GKE setup](#prerequisite-gke-setup) below)*

Steps:

1. Apply `custom-http-hc-ingress.yaml` file

   ```sh
   $ kubectl apply -f custom-http-hc-ingress.yaml
     ingress.networking.k8s.io/hc-test created
     backendconfig.cloud.google.com/hc-test created
     service/whereami created
     deployment.apps/whereami created
   $
   ```

2. Wait until all created objects reach desired state

3. Verify and enjoy

### Prerequisite: GKE setup

1. Enable GKE API

   ```sh
   gcloud services enable container.googleapis.com
   ```

2. Create simple zonal GKE cluster for tests

   ```sh
   gcloud container clusters create cluster-test \
   --zone europe-central2-a \
   --release-channel regular \
   --enable-ip-alias
   ```

3. Configure client credentials for a new cluster

   ```sh
   gcloud container clusters get-credentials cluster-test \
   --zone europe-central2-a
   ````
