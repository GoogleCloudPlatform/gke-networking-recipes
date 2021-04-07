# Multi-cluster Services with non-VPC native (routes-based) clusters

[Multi-cluster Services](https://cloud.google.com/kubernetes-engine/docs/concepts/multi-cluster-services) works seamlessly with VPC-native clusters. While VPC-native is the recommended type and the default for new clusters, non-VPC native clusters (also known as _routes-based clusters_) can still be configured to consume `ServiceExport`s from VPC-native clusters if you already have or need to use this cluster type.

### Use-cases

- Spreading an application between new VPC-native clusters and existing legacy routes-based clusters
- ???

### Relevant documentation

- [Creating a routes based cluster](https://cloud.google.com/kubernetes-engine/docs/how-to/routes-based-cluster)
- [VPC Routes overview](https://cloud.google.com/vpc/docs/routes)
- [Multi-cluster Services Concepts](https://cloud.google.com/kubernetes-engine/docs/concepts/multi-cluster-services)
- [Setting Up Multi-cluster Services](https://cloud.google.com/kubernetes-engine/docs/how-to/multi-cluster-services)

#### Versions

- GKE clusters on GCP
- 1.17 and later versions of GKE supported
- Tested and validatd with 1.YY.YY-gke.YYYY on Apr XXth 2021

### Networking Manifests

### Try it out

1. Download this repo and navigate to the `multi-cluster-services-basic` folder

    ```sh
    $ git clone https://github.com/GoogleCloudPlatform/gke-networking-recipes.git
    Cloning into 'gke-networking-recipes'...

    $ cd gke-networking-recipes/multi-cluster-services/multi-cluster-services-basic
    ```

    > This recipe uses the manifests from the `multi-cluster-services-basic` folder.

    > There are two manifests in the multi-cluster-services-basics folder:

    > - app.yaml is the manifest for the `whereami` Deployment and Service.
    > - export.yaml is the manifest for the `ServiceExport`, which will be deployed to indicate exporting service.

2. Deploy the two clusters `gke-1` and `gke-2` as specified in [cluster setup](../../cluster-setup.md).

3. Follow the steps for cluster registration with Hub in [cluster setup](../../cluster-setup.md).

4. Make a third cluster that uses routes-based networking that will consume `ServiceExport`s from `gke-1`. Making a routes-based cluster must be opted into with the flag `--no-enable-ip-alias`.

    ```
    gcloud container clusters create gke-routes-based --zone us-east1-b --release-channel rapid --workload-pool=${PROJECT}.svc.id.goog --no-enable-ip-alias
    ```

5. Now log into `gke-1` and deploy the `app.yaml` manifest. You can configure these contexts as shown [here](../../cluster-setup.md).

    ```bash
    $ kubectl --context=gke-1 apply -f app.yaml
    namespace/multi-cluster-demo unchanged
    deployment.apps/whereami created
    service/whereami created

    # Shows that pod is running and happy
    $ kubectl --context=gke-1 get deploy -n multi-cluster-demo
    NAME              READY   UP-TO-DATE   AVAILABLE   AGE
    whereami          1/1     1            1           44m
    ```

6. Now create ServiceExport in `export.yaml` to export service to other clusters.

    ```bash
    $ kubectl --context=gke-1 apply -f export.yaml
    serviceexport.net.gke.io/whereami created
    ```

6. It can take up to 5 minutes to propagate endpoints when initially exporting Service from a cluster. Create the same Namespace in `gke-routes-based` to indicate you want to import service, and inspect ServiceImport and Endpoints.

    ```bash
    # you can set up the context for `gke-routes-based` like so
    kubectl config rename-context XYXYXYXY gke-routes-based
    ```

    ```bash
    $ kubectl --context=gke-routes-based create ns multi-cluster-demo
    namespace/multi-cluster-demo created
    
    # Shows that service is imported and ClusterSetIP is assigned.
    $ kubectl --context=gke-routes-based get serviceimport -n multi-cluster-demo
    NAME       TYPE           IP              AGE
    whereami   ClusterSetIP   [10.124.4.24]   4m50s
    
    # Shows that endpoints are propagated.
    $ kubectl --context=gke-routes-based get endpoints -n multi-cluster-demo
    NAME                 ENDPOINTS        AGE
    gke-mcs-7pqvt62non   10.16.4.7:8080   6m1s
    ```

Now let's demonstrate some of the limitations of routes-based clusters. Routes-based clusters can *consume* multi cluster services from other VPC-native clusters in the same Hub, but *cannot export* services. Let's try it and show how it won't work.

1. Navigate to the `routes-based-cluster` folder to access another set of manifests exporting a Service named `whereami-routes`.

   ```bash
   $ cd ../routes-based-cluster
   ```

2. Deploy the `app-routes.yaml` and `export-routes.yaml` manifests into your `gke-routes-based` cluster.

   ```bash
   $ kubectl --context=gke-routes-based apply -f app-routes.yaml
   deployment.apps/whereami-routes created
   service/whereami-routes created

   $ kubectl --context=gke-routes-based apply -f export-routes.yaml
   serviceexport.net.gke.io/whereami-routes created
   ```

3. Like normal, the service will be available by its normal cluster-local DNS name when accessing it from the cluster it is in. However, while a ServiceImport will be created in `gke-1`, endpoints will not be propogated and connectivity will not work.

   ```bash
   # You CAN access the service by its normal cluster.local DNS name when you are in the gke-routes-based context
   $ kubectl --context=gke-routes-based  run -ti --rm --restart=Never --image=radial/busyboxplus:curl shell-$RANDOM -- curl whereami-routes.multi-cluster-demo.svc.cluster.local
   {"cluster_name":"gke-routes-based", ...

   # You CANNOT access the services by its multicluster clusterset.local DNS name in any cluster
   $ kubectl --context=gke-1  run -ti --rm --restart=Never --image=radial/busyboxplus:curl shell-$RANDOM -- curl whereami-routes.multi-cluster-demo.svc.clusterset.local
   curl: (7) Failed to connect to whereami-routes.multi-cluster-demo.svc.clusterset.local port 80: Connection refused

    # The ServiceImport exists but the endpoints do not
    $ kubectl --context=gke-1 get serviceimports -n multi-cluster-demo
    NAME              TYPE           IP                 AGE
    whereami          ClusterSetIP   ["10.12.1.1"]      4h26m
    whereami-routes   ClusterSetIP   ["10.12.11.179"]   4h7m  # <-- ServiceImport for the Service exported from the routes-based cluster
   
    $ kubectl --context=gke-1 get endpoints -n multi-cluster-demo
    NAME                 ENDPOINTS       AGE
    gke-mcs-7pqvt62non   10.8.0.6:8080   4h25m
    whereami             10.8.0.6:8080   5d3h
    # no endpoints for whereami-routes
   ```

    In this case, MCS is not able to establish connectivity to the routes-based cluster from 