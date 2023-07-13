# Single-cluster Gateway with Regional L7 Internal Load Balancing

This recipe provides a basic walk-through for setting up Single-cluster Gateway with the `gke-l7-rilb` GatewayClass, provisioning a regional internal HTTP/S Load Balancer.

To achieve this, we will:

- Deploy sample application with two different deployments, and two different labels, into the GKE cluster named `gke-1`
- Deploy a Gateway using the `gke-l7-rilb` single-cluster GatewayClass to the GKE cluster named `gke-1`
- Deploy an HTTPRoute to route external traffic between v1 of the sample application and v2 of the sample application to achieve traffic splitting.

### Relevant documentation

- [Gateway API](https://cloud.google.com/kubernetes-engine/docs/concepts/gateway-api)
- [Gateway API resources](https://cloud.google.com/kubernetes-engine/docs/concepts/gateway-api#gateway_resources)
- [Deploying Gateways](https://cloud.google.com/kubernetes-engine/docs/how-to/deploying-gateways)
- [Proxy-only subnets for internal HTTP(S) load balancers](https://cloud.google.com/load-balancing/docs/l7-internal/proxy-only-subnets)

## Setup

Set the project environment variable and gcloud configuration
```
$ export PROJECT_ID=your_project_id
$ gcloud config set project $PROJECT_ID
```

Enable the required GCP APIs.
```
$ gcloud services enable \
     container.googleapis.com 
```

Beware to [create a proxy-only subnet](https://cloud.google.com/load-balancing/docs/l7-internal/proxy-only-subnets#proxy_only_subnet_create) in the same region of the cluster you're going to create
```
gcloud compute networks subnets create SUBNET_NAME \
    --purpose=INTERNAL_HTTPS_LOAD_BALANCER \
    --role=ACTIVE \
    --region=REGION \
    --network=VPC_NETWORK_NAME \
    --range=CIDR_RANGE
```

[Create one GKE cluster](https://github.com/GoogleCloudPlatform/gke-networking-recipes/blob/master/cluster-setup.md#single-cluster-environment) if one is not running yet.

## Deploy the target applications to the cluster

Deploy the resources for the first application to the cluster. This includes the Namespace, Deployment, and Service objects for the application.

```
$ cat app-v1.yaml

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
$ kubectl apply -f app-v1.yaml
```

Deploy the resources for the second application to the cluster. This includes the Deployment, and Service objects for the application.

```
$ cat app-v2.yaml

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
$ kubectl apply -f app-v2.yaml
```

Now enable the [Gateway API Custom Resource Definitions (CRDs)](https://cloud.google.com/kubernetes-engine/docs/how-to/deploying-gateways#install_gateway_api_crds)
```
kubectl kustomize "github.com/kubernetes-sigs/gateway-api/config/crd?ref=v0.3.0" | kubectl apply -f -
```

Check that presence of the Gateway classes, gke-l7-gxlb and gke-l7-rilb should be available and listed:
```
kubectl get gatewayclass
```

## Deploy the Gateway and HTTPRoute

Once the applications have been deployed, we can then configure an internal Gateway using the `gke-l7-rilb` GatewayClass. This GatewayClass will create an internal HTTP/S Load Balancer configured to distribute traffic across your target cluster.

Deploy the resources for the Single-cluster Gateway. This includes a Gateway utilizing the `gke-l7-rilb` GatewayClass and selecting on HTTPRoutes with the label `gateway: single-cluster-gateway-rilb`.

```
$ cat gateway.yaml

kind: Gateway
apiVersion: networking.x-k8s.io/v1alpha1
metadata:
  name: single-cluster-gateway-rilb
  namespace: store
spec:
  gatewayClassName: gke-l7-rilb
  listeners:  
  - protocol: HTTP
    port: 80
    routes:
      kind: HTTPRoute
      selector:
        matchLabels:
          gateway: single-cluster-gateway-rilb
```

Deploy the `store-route-ilb` HTTPRoute resource to the config cluster. 

```
$ cat route.yaml

kind: HTTPRoute
apiVersion: networking.x-k8s.io/v1alpha1
metadata:
  name: store-route-ilb
  namespace: store
  labels:
    gateway: single-cluster-gateway-rilb
spec:
  hostnames:
  - "store.example.internal"
  rules:
  - forwardTo:
    - serviceName: store-v1
      port: 8080
      weight: 50
    - serviceName: store-v2
      port: 8080
      weight: 50
```

This HTTPRoute will allow users to take advantage of features in the `gke-l7-rilb ` GatewayClass like traffic weighting. In this scenario, we specify the `weight` fields in the HTTPRoute to send 50% of traffic to the application version `store-v1` and 50% of traffic to the application version `store-v2`.

/////
## Validate successful deployment of an internal Single-cluster Gateway

Create a client VM to access the internal Single-cluster Gateway.

```
$ gcloud compute instances create client-host \
--image-family=debian-9 \
--image-project=debian-cloud \
--zone=europe-west2-a \
--tags=allow-ssh,http-server,https-server
```

Grab the internal IP address for the Single-cluster Gateway.

```
$ kubectl -n store get gateway single-cluster-gateway-rilb -o=jsonpath="{.status.addresses[0].value}"
```

SSH into the client VM. 
```
$ gcloud beta compute ssh client-host --zone=europe-west2-a
```

Confirm that as we issue requests to the Single-cluster Regional L7 Internal Balancer with traffic weighting configured; we are seeing half traffic requests served from application `store-v1` and half requests being served from application with metadata `store-v2`.

```
$ while true; do curl -H "host: store.example.internal" http://VIP; sleep 2; done
```

## Clean-up


```
```