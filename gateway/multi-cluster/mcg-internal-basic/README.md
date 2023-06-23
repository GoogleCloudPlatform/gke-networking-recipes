# Basic Multi-cluster Gateway with Internal Load Balancing

This recipe provides a basic walk through for setting up Multi-cluster Gateway with the `gke-l7-rilb-mc` GatewayClass, provisioning an internal HTTP/S Load Balancer across multiple GKE clusters.

To achieve this, we will:

- Deploy v1 of a sample application into the GKE cluster named `gke-1`, as well as its ServiceExport.
- Deploy v2 of a sample application into the GKE cluster named `gke-2`, as well as its ServiceExport.
- Deploy a Gateway using the `gke-l7-rilb-mc` multi-cluster GatewayClass to the GKE cluster named `gke-1`, serving as this example's config cluster.
- Deploy an HTTPRoute to route external traffic between v1 of the sample application in `gke-1` and v2 of the sample application in `gke-2`.

## Setup

Enable the required GCP APIs.
```
$ gcloud services enable \
     container.googleapis.com \
     gkehub.googleapis.com \
     multiclusterservicediscovery.googleapis.com \
     multiclusteringress.googleapis.com \ 
     trafficdirector.googleapis.com
```
Create two GKE clusters.
```
$ gcloud container clusters create gke-1 \
  --zone=us-west1-a \
  --enable-ip-alias \
  --workload-pool=PROJECT_ID.svc.id.goog \
  --release-channel=rapid \
  --cluster-version=1.20
```
```
$ gcloud container clusters create gke-2 \
  --zone=us-west1-a \
  --enable-ip-alias \
  --workload-pool=PROJECT_ID.svc.id.goog \
  --release-channel=rapid \
  --cluster-version=1.20
```
Register the clusters to the appropriate Environs.
```
$ gcloud alpha container hub memberships register gke-1 \
   --gke-cluster us-west1-a/gke-1 \
   --enable-workload-identity

$ gcloud alpha container hub memberships register gke-2 \
   --gke-cluster us-west1-a/gke-2 \
   --enable-workload-identity
```

Enable multi-cluster services for the registered clusters.
```
$ gcloud alpha container hub multi-cluster-services enable \
    --project PROJECT_ID

$ gcloud projects add-iam-policy-binding PROJECT_ID \
    --member "serviceAccount:PROJECT_ID.svc.id.goog[gke-mcs/gke-mcs-importer]" \
    --role "roles/compute.networkViewer
```

Enable multi-cluster Ingress for the registered clusters.
```
$ gcloud alpha container hub ingress enable \
  --config-membership=projects/PROJECT_NUMBER/locations/global/memberships/gke-1 \
  --billing=standalone
```

## Deploy the target applications across multiple clusters

Deploy the resources for the first application to `gke-1`. This includes the Namespace, Deployment, and Service objects for the application.

```
$ cat gke-1/app-v1.yaml

kind: Namespace
apiVersion: v1
metadata:
  name: store
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: store-v1
  namespace: store
spec:
  replicas: 2
  selector:
    matchLabels:
      app: store
      version: v1
  template:
    metadata:
      labels:
        app: store
        version: v1
    spec:
      containers:
      - name: whereami
        image: us-docker.pkg.dev/google-samples/containers/gke/whereami:v1.2.20
        ports:
          - containerPort: 8080
        env:
        - name: METADATA
          value: "store-v1"
---
apiVersion: v1
kind: Service
metadata:
  name: store-v1
  namespace: store
spec:
  selector:
    app: store
    version: v1
  ports:
  - port: 8080
    targetPort: 8080
```

```
$ kubectl apply -f gke-1/app-v1.yaml
```
Now deploy the `ServiceExport` for this service.
```
$ kubectl apply -f gke-1/serviceexport-v1.yaml
```

Deploy the resources for the second application to `gke-2`. This includes the Namespace, Deployment, and Service objects for the application.

```
$ cat gke-2/app-v2.yaml

kind: Namespace
apiVersion: v1
metadata:
  name: store
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: store-v2
  namespace: store
spec:
  replicas: 2
  selector:
    matchLabels:
      app: store
      version: v2
  template:
    metadata:
      labels:
        app: store
        version: v2
    spec:
      containers:
      - name: whereami
        image: us-docker.pkg.dev/google-samples/containers/gke/whereami:v1.2.20
        ports:
          - containerPort: 8080
        env:
        - name: METADATA
          value: "store-v2"
---
apiVersion: v1
kind: Service
metadata:
  name: store-v2
  namespace: store
spec:
  selector:
    app: store
    version: v2
  ports:
  - port: 8080
    targetPort: 8080
```
```
$ kubectl apply -f gke-2/app-v2.yaml
```
Now deploy the `ServiceExport` for this service.
```
$ kubectl apply -f gke-2/serviceexport-v2.yaml
```

## Deploy the Gateway and HTTPRoute

Once the applications have been deployed, we can then configure an internal Gateway using the `gke-l7-rilb-mc` GatewayClass. This GatewayClass will create an internal HTTP/S Load Balancer configured to distribute traffic across your target clusters.

Deploy the resources for the Multi-cluster Gateway. This includes a Gateway utilizing the `gke-l7-rilb-mc` GatewayClass and selecting on HTTPRoutes with the label `gateway: multi-cluster-gateway-ilb`.

```
$ cat gke-1/gateway.yaml

kind: Gateway
apiVersion: networking.x-k8s.io/v1alpha1
metadata:
  name: multi-cluster-gateway-ilb
  namespace: store
spec:
  gatewayClassName: gke-l7-rilb-mc
  listeners:  
  - protocol: HTTP
    port: 80
    routes:
      kind: HTTPRoute
      selector:
        matchLabels:
          gateway: multi-cluster-gateway-ilb
```

Deploy the `store-route-ilb` HTTPRoute resource to the config cluster. 

```
$ cat gke-1/route.yaml

kind: HTTPRoute
apiVersion: networking.x-k8s.io/v1alpha1
metadata:
  name: store-route-ilb
  namespace: store
  labels:
    gateway: multi-cluster-gateway-ilb
spec:
  rules:
  - forwardTo:
    - backendRef:
        group: net.gke.io
        kind: ServiceImport
        name: store-v1
      port: 8080
      weight: 80
    - backendRef:
        group: net.gke.io
        kind: ServiceImport
        name: store-v2
      port: 8080
      weight: 20
```

This HTTPRoute will allow users to take advantage of features in the `gke-l7-rilb-mc ` GatewayClass like traffic weighting. In this scenario, we specify the `weight` fields in the HTTPRoute to send 80% of traffic to `store-v1` in cluster `gke-1` and 20% of traffic to `store-v2` in `gke-2`.

## Validate successful deployment of an internal Multi-cluster Gateway

Create a client VM to access the internal Multi-cluster Gateway.

```
$ gcloud compute instances create client-host \
--image-family=debian-9 \
--image-project=debian-cloud \
--zone=us-west1-a \
--tags=allow-ssh,http-server,https-server
```

Grab the internal IP address for the Multi-cluster Gateway.

```
$ kubectl get gateway multi-cluster-gateway-ilb -o=jsonpath="{.status.addresses[0].value}")
```

SSH into the client VM. 
```
$ gcloud beta compute ssh client-host --zone=us-west1-a 
```

Confirm that as we issue requests to the Multi-cluster Gateway with traffic weighting configured; we are seeing more traffic served from `store-v1` running in `gke-1` than `store-v2` running in `gke-2`.

```
$ while true; do curl http://VIP; sleep 2; done
```