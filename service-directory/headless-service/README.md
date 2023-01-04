# Service Directory GKE Integration - Headless Service

Service Directory for GKE is a cloud-hosted controller for GKE Clusters that
syncs Kubernetes Services to Service Directory.

This example syncs a Headless service deployed on GKE to Service Directory. See
the [headless-service.yaml](headless-service.yaml) manifest for the full
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

This recipe demonstrates deploying a Headless Service and creating a
ServiceDirectoryRegistrationPolicy that enables the Service to sync to Service
Directory.

The ServiceDirectoryRegistrationPolicy is the Custom Resource (CR) that is
created for each Kubernetes Namespace that should be synced to Service
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
    [headless-service.yaml](headless-service.yaml) manifest.

    ```bash
    $ kubectl apply -f headless-service.yaml
    namespace/service-directory-demo created
    service/whereami created
    deployment.apps/whereami created
    servicedirectoryregistrationpolicy.networking.gke.io/default created
    ```

1.  Insepct the headless service.

    ```bash
    $ kubectl describe services/whereami -n service-directory-demo
    Name:              whereami
    Namespace:         service-directory-demo
    Labels:            app=whereami
                       sd-import=true
    Annotations:       description: Describes the location of the service
    Selector:          app=whereami
    Type:              ClusterIP
    IP:                None
    Port:              <unset>  80/TCP
    TargetPort:        8080/TCP
    Endpoints:         10.112.0.28:8080,10.112.0.29:8080,10.112.0.30:8080
    Session Affinity:  None
    Events:            <none>
    ```

1.  Validate that the service has synced to Service Directory by resolving the
    service in the region that your GKE cluster exists in.

    ```bash
    $ gcloud service-directory services resolve whereami --namespace=service-directory-demo --location=us-west1
    service:
      endpoints:
      - address: 10.112.0.30
        annotations:
          description: Describes the location of the service
        name: projects/my-project/locations/us-west1/namespaces/service-directory-demo/services/whereami/endpoints/my-cluster-2679379489
        port: 8080
      - address: 10.112.0.28
        annotations:
          description: Describes the location of the service
        name: projects/my-project/locations/us-west1/namespaces/service-directory-demo/services/whereami/endpoints/my-cluster-2140213467
        port: 8080
      - address: 10.112.0.29
        annotations:
          description: Describes the location of the service
        name: projects/my-project/locations/us-west1/namespaces/service-directory-demo/services/whereami/endpoints/my-cluster-4196602425
        port: 8080
      name: projects/my-project/locations/us-west1/namespaces/service-directory-demo/services/whereami
    ```

1.  Scale up the deployment of the Headless Service.

    ```bash
    $ kubectl scale deployment.v1.apps/whereami -n service-directory-demo --replicas=5
    deployment.apps/whereami scaled
    ```

1.  Inspect the deployment.

    ```bash
    $ kubectl describe deployment.v1.apps/whereami -n service-directory-demo
    Name:                   whereami
    Namespace:              service-directory-demo
    CreationTimestamp:      Wed, 14 Jul 2021 13:26:11 -0400
    Labels:                 <none>
    Annotations:            deployment.kubernetes.io/revision: 1
    Selector:               app=whereami
    Replicas:               5 desired | 5 updated | 5 total | 5 available | 0 unavailable
    StrategyType:           RollingUpdate
    MinReadySeconds:        0
    RollingUpdateStrategy:  25% max unavailable, 25% max surge
    Pod Template:
      Labels:  app=whereami
      Containers:
       whereami:
        Image:        gcr.io/google-samples/whereami:v1.0.1
        Port:         8080/TCP
        Host Port:    0/TCP
        Readiness:    http-get http://:8080/healthz delay=5s timeout=1s period=10s #success=1 #failure=3
        Environment:  <none>
        Mounts:       <none>
      Volumes:        <none>
    Conditions:
      Type           Status  Reason
      ----           ------  ------
      Progressing    True    NewReplicaSetAvailable
      Available      True    MinimumReplicasAvailable
    OldReplicaSets:  <none>
    NewReplicaSet:   whereami-869976468f (5/5 replicas created)
    Events:
      Type    Reason             Age   From                   Message
      ----    ------             ----  ----                   -------
      Normal  ScalingReplicaSet  108s  deployment-controller  Scaled up replica set whereami-869976468f to 3
      Normal  ScalingReplicaSet  15s   deployment-controller  Scaled up replica set whereami-869976468f to 5
    ```

1.  Validate that the service has been updated in Service Directory with the new
    Pod endpoints that are running the service.

    ```bash
    $ gcloud service-directory services resolve whereami --namespace=service-directory-demo --location=us-west1
    service:
      endpoints:
      - address: 10.112.0.28
        annotations:
          description: Describes the location of the service
        name: projects/my-project/locations/us-west1/namespaces/service-directory-demo/services/whereami/endpoints/my-cluster-2140213467
        port: 8080
      - address: 10.112.0.30
        annotations:
          description: Describes the location of the service
        name: projects/my-project/locations/us-west1/namespaces/service-directory-demo/services/whereami/endpoints/my-cluster-2679379489
        port: 8080
      - address: 10.112.0.29
        annotations:
          description: Describes the location of the service
        name: projects/my-project/locations/us-west1/namespaces/service-directory-demo/services/whereami/endpoints/my-cluster-4196602425
        port: 8080
      - address: 10.112.0.32
        annotations:
          description: Describes the location of the service
        name: projects/my-project/locations/us-west1/namespaces/service-directory-demo/services/whereami/endpoints/my-cluster-4262052618
        port: 8080
      - address: 10.112.0.31
        annotations:
          description: Describes the location of the service
        name: projects/my-project/locations/us-west1/namespaces/service-directory-demo/services/whereami/endpoints/my-cluster-1912131955
        port: 8080
      name: projects/my-project/locations/us-west1/namespaces/service-directory-demo/services/whereami
    ```

### Cleanup

```bash
kubectl delete -f headless-service.yaml
```
