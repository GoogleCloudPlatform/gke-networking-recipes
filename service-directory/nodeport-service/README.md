# Service Directory GKE Integration - NodePort Service

Service Directory for GKE is a cloud-hosted controller for GKE Clusters that
syncs Kubernetes Services to Service Directory.

This example syncs a NodePort Service deployed on GKE to Service Directory. See
the [nodeport-service.yaml](nodeport-service.yaml) manifest for the full
deployment spec.

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

This recipe demonstrates deploying a NodePort Service and creating a
ServiceDirectoryRegistrationPolicy that enables the Service to sync to Service
Directory.

The ServiceDirectoryRegistrationPolicy is the Custom Resource (CR) that is
created for each Kubernetes namespace that should be synced to Service
Directory.

The ServiceDirectoryRegistrationPolicy below will sync:

*   Services with the label `sd-import: "true"`
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
    [nodeport-service.yaml](nodeport-service.yaml) manifest.

    ```bash
    $ kubectl apply -f nodeport-service.yaml
    namespace/service-directory-demo created
    service/whereami created
    deployment.apps/whereami created
    servicedirectoryregistrationpolicy.networking.gke.io/default created
    ```

1.  Insepct the NodePort Service.

    ```bash
    $ kubectl describe services/whereami -n service-directory-demo
    Name:                     whereami
    Namespace:                service-directory-demo
    Labels:                   app=whereami
                            sd-import=true
    Annotations:              description: Describes the location of the service
    Selector:                 app=whereami
    Type:                     NodePort
    IP:                       10.115.243.185
    Port:                     <unset>  80/TCP
    TargetPort:               8080/TCP
    NodePort:                 <unset>  30007/TCP
    Endpoints:                10.112.0.36:8080,10.112.0.38:8080
    Session Affinity:         None
    External Traffic Policy:  Cluster
    Events:                   <none>
    ```

1.  Inspect the Nodes in which the Pods are running on

    **Note: The cluster used in this example only had 1 node.**

    ```bash
    $ kubectl describe nodes
    Name:               gke-my-cluster-default-pool-0b5e50ae-1m08
    Roles:              <none>
    Labels:             beta.kubernetes.io/arch=amd64
                        beta.kubernetes.io/instance-type=e2-medium
                        beta.kubernetes.io/os=linux
                        cloud.google.com/gke-boot-disk=pd-standard
                        cloud.google.com/gke-container-runtime=containerd
                        cloud.google.com/gke-nodepool=default-pool
                        cloud.google.com/gke-os-distribution=cos
                        cloud.google.com/machine-family=e2
                        failure-domain.beta.kubernetes.io/region=us-west1
                        failure-domain.beta.kubernetes.io/zone=us-west1-b
                        kubernetes.io/arch=amd64
                        kubernetes.io/hostname=gke-my-cluster-default-pool-0b5e50ae-1m08
                        kubernetes.io/os=linux
                        node.kubernetes.io/instance-type=e2-medium
                        topology.gke.io/zone=us-west1-b
                        topology.kubernetes.io/region=us-west1
                        topology.kubernetes.io/zone=us-west1-b
    Annotations:        container.googleapis.com/instance_id: 3941714257799828844
                        csi.volume.kubernetes.io/nodeid:
                          {"pd.csi.storage.gke.io":"projects/my-project/zones/us-west1-b/instances/gke-my-cluster-default-pool-0b5e50ae-1m08"}
                        node.alpha.kubernetes.io/ttl: 0
                        node.gke.io/last-applied-node-labels:
                          cloud.google.com/gke-boot-disk=pd-standard,cloud.google.com/gke-container-runtime=containerd,cloud.google.com/gke-nodepool=default-pool,cl...
                        volumes.kubernetes.io/controller-managed-attach-detach: true
    CreationTimestamp:  Tue, 13 Jul 2021 15:39:32 -0400
    Addresses:
      InternalIP:   10.138.15.194
      ExternalIP:   35.247.115.52
      InternalDNS:  gke-my-cluster-default-pool-0b5e50ae-1m08.c.my-project.internal
      Hostname:     gke-my-cluster-default-pool-0b5e50ae-1m08.c.my-project.internal
    PodCIDR:                      10.112.0.0/24
    PodCIDRs:                     10.112.0.0/24
    ```

1.  Validate that the service has synced to Service Directory by resolving the
    service in the region that your GKE cluster exists in.

    ```bash
    $ gcloud service-directory services resolve whereami --namespace=service-directory-demo --location=us-west1
    service:
      endpoints:
      - address: 10.138.15.194
        annotations:
          description: Describes the location of the service
        name: projects/my-project/locations/us-west1/namespaces/service-directory-demo/services/whereami/endpoints/my-cluster-2998672570
        port: 30007
      name: projects/my-project/locations/us-west1/namespaces/service-directory-demo/services/whereami
    ```

### Cleanup

```bash
kubectl delete -f nodeport-service.yaml
```
