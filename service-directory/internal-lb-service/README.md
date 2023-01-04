# Service Directory GKE Integration - Internal LoadBalancer Service

Service Directory for GKE is a cloud-hosted controller for GKE Clusters that
syncs Kubernetes Services to Service Directory.

This example syncs an Internal Load Balancer service deployed on GKE to Service
Directory. See the
[internal-lb-service.yaml](internal-lb-service.yaml) manifest for
the full deployment spec.

### Use-cases

*   Manage and discover services across heterogenous environments.
*   Access services through multiple clients, and standardize service
    consumption regardless of infrastructure
*   Easy-to-maintain service registry

### Relevant Documentation

*   [Service Directory Concepts](https://cloud.google.com/service-directory/docs/concepts)
*   [Service Directory with GKE Overview](https://cloud.google.com/service-directory/docs/sd-gke-overview)
*   [Configuring Service Directory for GKE](https://cloud.google.com/service-directory/docs/configuring-sd-for-gke)

#### Versions

*   GKE clusters on GCP
*   All versions of GKE supported

### Networking Manifests

This recipe demonstrates deploying a LoadBalancer Service and creating a
ServiceDirectoryRegistrationPolicy that enables the Service to sync to Service
Directory.

The ServiceDirectoryRegistrationPolicy is the Custom Resource (CR) that is
created for each Kubernetes Namespace that should be synced to Service
Directory.

The ServiceDirectoryRegistrationPolicy below will sync:

*   Services with the label `sd-import: "true"`
*   Annotations with the key `cloud.google.com/load-balancer-type`
*   Annotations with the key `description`

```yaml
apiVersion: networking.gke.io/v1alpha1
kind: ServiceDirectoryRegistrationPolicy
metadata:
  # Only the name "default" is allowed
  name: default
  namespace: service-directory-demo
spec:
  resources:
    - kind: Service
      selector:
        matchLabels:
          sd-import: "true"
      annotationsToSync:
      - cloud.google.com/load-balancer-type
      - description
```

### Try it out

1.  Download this repo and navigate to this folder.

    ```bash
    $ git clone https://github.com/GoogleCloudPlatform/gke-networking-recipes.git
    Cloning into 'gke-networking-recipes'...

    $ cd gke-networking-recipes/service-directory
    ```

1.  Create a GKE Cluster and register it with your fleet following the
    instructions
    [here](https://cloud.google.com/anthos/multicluster-management/connect/registering-a-cluster)

1.  Enable the Service Directory feature on your fleet.

    ```bash
    $ gcloud alpha container hub service-directory enable
    ```

1.  Deploy the Namespace, Deployment, Service, and
    ServiceDirectoryRegistrationPolicy resources in the
    [internal-lb-service.yaml](internal-lb-service.yaml) manifest.

    ```bash
    $ kubectl apply -f internal-lb-service.yaml
    namespace/service-directory-demo created
    service/whereami created
    deployment.apps/whereami created
    servicedirectoryregistrationpolicy.networking.gke.io/default created
    ```

1.  It can take a few minutes for the internal LoadBalancer IP of the Service
    resource to be ready. Insepct the LoadBalancer Service.

    ```bash
    $ kubectl describe services/whereami -n service-directory-demo
    Name:                     whereami
    Namespace:                service-directory-demo
    Labels:                   app=whereami
                              sd-import=true
    Annotations:              cloud.google.com/load-balancer-type: Internal
                              description: Describes the location of the service
    Selector:                 app=whereami
    Type:                     LoadBalancer
    IP:                       10.115.242.74
    LoadBalancer Ingress:     10.138.15.197
    Port:                     <unset>  80/TCP
    TargetPort:               8080/TCP
    NodePort:                 <unset>  30544/TCP
    Endpoints:                10.112.0.22:8080,10.112.0.23:8080,10.112.0.24:8080
    Session Affinity:         None
    External Traffic Policy:  Cluster
    Events:
      Type    Reason                Age   From                Message
      ----    ------                ----  ----                -------
      Normal  EnsuringLoadBalancer  64s   service-controller  Ensuring load balancer
      Normal  EnsuredLoadBalancer   2s    service-controller  Ensured load balancer
    ```

1.  Validate that the service has synced to Service Directory by resolving the
    service in the region that your GKE cluster exists in.

    ```bash
    $ gcloud service-directory services resolve whereami --namespace=service-directory-demo --location=us-west1

    service:
      endpoints:
      - address: 10.138.15.197
        annotations:
          cloud.google.com/load-balancer-type: Internal
          description: Describes the location of the service
        name: projects/my-project/locations/us-west1/namespaces/service-directory-demo/services/whereami/endpoints/my-cluster-1762298646
        port: 80
      name: projects/my-project/locations/us-west1/namespaces/service-directory-demo/services/whereami
    ```

### Cleanup

```bash
kubectl delete -f internal-lb-service.yaml
```
