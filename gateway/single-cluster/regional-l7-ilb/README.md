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

### Gateway API v1 Migration Notes

This recipe has been updated to use the stable Gateway API v1 specification. Key changes from earlier versions:

#### API Version Updates
- **Gateway**: `networking.x-k8s.io/v1alpha1` → `gateway.networking.k8s.io/v1`
- **HTTPRoute**: `networking.x-k8s.io/v1alpha1` → `gateway.networking.k8s.io/v1`

#### HTTPRoute Field Changes
- **Backend References**: `forwardTo` → `backendRefs`
- **Service Name**: `serviceName` → `name`

#### Gateway API CRD Version
- Updated from `v0.3.0` to `v1.2.0` for stable v1 API support

If you're migrating from an older version, ensure your GKE cluster supports Gateway API v1 (available in GKE 1.24+).

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

Create a [proxy-only subnet](https://cloud.google.com/load-balancing/docs/proxy-only-subnets) in the same region as your GKE cluster. This subnet is required for the internal HTTP(S) Load Balancer to function properly.

**Important**: You must create the proxy-only subnet before deploying the Gateway resources.

```bash
gcloud compute networks subnets create proxy-only-subnet \
    --purpose=REGIONAL_MANAGED_PROXY \
    --role=ACTIVE \
    --region=REGION \
    --network=VPC_NETWORK_NAME \
    --range=10.129.0.0/23
```

**Proxy-only Subnet Requirements (2024-2025 Updates)**:
- Use `--purpose=REGIONAL_MANAGED_PROXY` for regional internal load balancers
- Minimum subnet size: `/26` (64 IP addresses)  
- Recommended size: `/23` (512 IP addresses) for better scalability
- Create one proxy-only subnet per region in your VPC network
- Ensure firewall rules allow traffic from the proxy-only subnet to your backend services

**Firewall Configuration**: If using a custom VPC network, create a firewall rule to allow health checks:
```bash
gcloud compute firewall-rules create allow-proxy-only-subnet \
    --direction=INGRESS \
    --priority=1000 \
    --network=VPC_NETWORK_NAME \
    --action=ALLOW \
    --rules=tcp:80,tcp:443,tcp:8080 \
    --source-ranges=10.129.0.0/23 \
    --target-tags=gke-node
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

**Note**: This command has been updated to use Gateway API v1.2.0 which includes stable v1 API support:
```
kubectl kustomize "github.com/kubernetes-sigs/gateway-api/config/crd?ref=v1.2.0" | kubectl apply -f -
```

Check that presence of the Gateway classes, gke-l7-gxlb and gke-l7-rilb should be available and listed:

```
kubectl get gatewayclass
```
| NAME | CONTROLLER | ACCEPTED |
|---|---|---|
| gke-l7-global-external-managed | networking.gke.io/gateway | True |
| gke-l7-gxlb | networking.gke.io/gateway | True |
| gke-l7-regional-external-managed | networking.gke.io/gateway | True |
| gke-l7-rilb | networking.gke.io/gateway | True |
| gke-passthrough-lb-external-managed | networking.gke.io/persistent-ip-controller | True |
| gke-passthrough-lb-internal-managed | networking.gke.io/persistent-ip-controller | True |
| gke-persistent-fast-regional-external-managed | networking.gke.io/persistent-ip-controller | True |
| gke-persistent-fast-regional-internal-managed | networking.gke.io/persistent-ip-controller | True |
| gke-persistent-regional-external-managed | networking.gke.io/persistent-ip-controller | True |
| gke-persistent-regional-internal-managed | networking.gke.io/persistent-ip-controller | True |

## Deploy the Gateway and HTTPRoute

Once the applications have been deployed, we can then configure an internal Gateway using the `gke-l7-rilb` GatewayClass. This GatewayClass will create an internal HTTP/S Load Balancer configured to distribute traffic across your target cluster.

Deploy the resources for the Single-cluster Gateway. This includes a Gateway utilizing the `gke-l7-rilb` GatewayClass and selecting on HTTPRoutes with the label `gateway: single-cluster-gateway-rilb`.

```
kubectl apply -f gateway.yaml
```

Deploy the `store` HTTPRoute resource to the config cluster. 

```
 kubectl apply -f route.yaml 
```

This HTTPRoute will allow users to take advantage of features in the `gke-l7-rilb ` GatewayClass like traffic weighting. In this scenario, we specify the `weight` fields in the `backendRefs` to send 50% of traffic to the application version `store-v1` and 50% of traffic to the application version `store-v2`.

**Note**: This HTTPRoute uses the updated Gateway API v1 specification with `backendRefs` instead of the deprecated `forwardTo` field.

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

Get the Internal IP address for the Single-cluster Gateway.

```
$ kubectl -n store get gateway single-cluster-gateway-rilb -o=jsonpath="{.status.addresses[0].value}"
```

SSH into the client VM. 
```
$ gcloud beta compute ssh client-host --zone=$ZONE
```

Confirm that as we issue requests to the Single-cluster Regional L7 Internal Balancer with traffic weighting configured; we are seeing half traffic requests served from application `store-v1` and half requests being served from application with metadata `store-v2`.

```
$ while true; do curl -H "host: store.example.internal" http://VIP; sleep 2; done
```

## Clean-up


```
```