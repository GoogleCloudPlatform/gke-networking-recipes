# gRPC on Gateway Controller

End-to-end example of gRPC Load Balancing with gRPC:

* Deploy gRPC application on GKE
* Enable Gateways to handle both internet facing and internal-only traffic.
* Verify gRPC LoadBalancing through Gateway

---

First deploy a GKE cluster with NEG enabled:

```bash
gcloud container  clusters create cluster-1 --machine-type "n1-standard-2" \
 --zone us-central1-a  --num-nodes 2 --enable-ip-alias  \
 --cluster-version "1.20"  -q
```

Install Gateway CRDs

```
kubectl kustomize "github.com/kubernetes-sigs/gateway-api/config/crd?ref=v0.3.0" \
| kubectl apply -f -
```


optionally create SSL Certificate for use with statically defined certificates (`networking.gke.io/pre-shared-certs`)

```bash
gcloud compute ssl-certificates create gcp-cert-grpc-global \
   --global --certificate server.crt --private-key server.key 

gcloud compute ssl-certificates create gcp-cert-grpc-us-central \
   --region=us-central1 --certificate server.crt --private-key server.key 
```

or use the default `spec.listeners.tls.certificateRef`.   For reference see [GatewayClass capabilities](https://cloud.google.com/kubernetes-engine/docs/how-to/gatewayclass-capabilities#gateway)

Wait maybe 10 mins for the Gateway controllers to get initialized.

Deploy application

```bash
kubectl apply -f .
```

> Please note the deployments here use the health_check proxy and sample gRPC applications hosted on `docker.io/`.  You can build and deploy these images into your own repository as well.

Wait another 8mins for the IP address for the loadbalancers to get initialized

Check gateway status

```bash
$ kubectl get gatewayclass,gateway
NAME                                           CONTROLLER
gatewayclass.networking.x-k8s.io/gke-l7-gxlb   networking.gke.io/gateway
gatewayclass.networking.x-k8s.io/gke-l7-rilb   networking.gke.io/gateway

NAME                                         CLASS
gateway.networking.x-k8s.io/gke-l7-gxlb-gw   gke-l7-gxlb
gateway.networking.x-k8s.io/gke-l7-rilb-gw   gke-l7-rilb
```


Get Gateway IPs

```bash
export GW_XLB_VIP=$(kubectl get gateway gke-l7-gxlb-gw -o json | jq '.status.addresses[].value' -r)
echo $GW_XLB_VIP


export GW_ILB_VIP=$(kubectl get gateway gke-l7-rilb-gw -o json | jq '.status.addresses[].value' -r)
echo $GW_ILB_VIP
```

#### Test External

Verify external loadbalancing by transmitting 10 RPCs over one channel.  The responses will show different pods that handled each request

```bash
$ docker run --add-host grpc.domain.com:$GW_XLB_VIP  \
  -t docker.io/salrashid123/grpc_app /grpc_client \
   --host=grpc.domain.com:443 --tlsCert /certs/CA_crt.pem \
   --servername grpc.domain.com --repeat 10

I0605 12:43:17.257595       1 grpc_client.go:104] RPC HealthChekStatus: SERVING
I0605 12:43:17.290574       1 grpc_client.go:112] RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-69787f4986-ql77m"
I0605 12:43:17.329472       1 grpc_client.go:112] RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-69787f4986-ql77m"
I0605 12:43:17.373584       1 grpc_client.go:112] RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-69787f4986-ql77m"
I0605 12:43:17.405143       1 grpc_client.go:112] RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-69787f4986-ql77m"
I0605 12:43:17.443893       1 grpc_client.go:112] RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-69787f4986-dfbk7"
I0605 12:43:17.481249       1 grpc_client.go:112] RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-69787f4986-ql77m"
I0605 12:43:17.527853       1 grpc_client.go:112] RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-69787f4986-dfbk7"
I0605 12:43:17.565236       1 grpc_client.go:112] RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-69787f4986-dfbk7"
I0605 12:43:17.648080       1 grpc_client.go:112] RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-69787f4986-ql77m"
I0605 12:43:17.687119       1 grpc_client.go:112] RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-69787f4986-ql77m
```

Now scale the number of pods

```bash
$ kubectl scale --replicas=10 deployment.apps/fe-deployment

$ kubectl get po
NAME                             READY   STATUS    RESTARTS   AGE
fe-deployment-69787f4986-29tl7   2/2     Running   0          10s
fe-deployment-69787f4986-2v9sn   2/2     Running   0          10s
fe-deployment-69787f4986-8g67x   2/2     Running   0          10s
fe-deployment-69787f4986-bqd9s   2/2     Running   0          10s
fe-deployment-69787f4986-dfbk7   2/2     Running   0          6m19s
fe-deployment-69787f4986-dmszq   2/2     Running   0          9s
fe-deployment-69787f4986-mm27x   2/2     Running   0          9s
fe-deployment-69787f4986-nkzqm   2/2     Running   0          10s
fe-deployment-69787f4986-ql77m   2/2     Running   0          6m19s
fe-deployment-69787f4986-wdhbm   2/2     Running   0          10s
```

Rerun the test. Notice the new pods in the response

```bash
$ docker run --add-host grpc.domain.com:$GW_XLB_VIP  \
  -t docker.io/salrashid123/grpc_app /grpc_client \
   --host=grpc.domain.com:443 --tlsCert /certs/CA_crt.pem \
   --servername grpc.domain.com --repeat 10

I0605 12:44:57.352989       1 grpc_client.go:104] RPC HealthChekStatus: SERVING
I0605 12:44:57.396556       1 grpc_client.go:112] RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-69787f4986-nkzqm"
I0605 12:44:57.438540       1 grpc_client.go:112] RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-69787f4986-8g67x"
I0605 12:44:57.480235       1 grpc_client.go:112] RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-69787f4986-29tl7"
I0605 12:44:57.522557       1 grpc_client.go:112] RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-69787f4986-ql77m"
I0605 12:44:57.556786       1 grpc_client.go:112] RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-69787f4986-8g67x"
I0605 12:44:57.599521       1 grpc_client.go:112] RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-69787f4986-dfbk7"
I0605 12:44:57.640972       1 grpc_client.go:112] RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-69787f4986-bqd9s"
I0605 12:44:57.682497       1 grpc_client.go:112] RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-69787f4986-bqd9s"
I0605 12:44:57.715570       1 grpc_client.go:112] RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-69787f4986-ql77m"
I0605 12:44:57.757088       1 grpc_client.go:112] RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-69787f4986-wdh
```

#### Test Internal

To test the internal loadbalancer, you must configure a VM from within an [allocated network](https://cloud.google.com/load-balancing/docs/l7-internal/setting-up-l7-internal#configuring_the_proxy-only_subnet) and export the environment variable `$GW_ILB_VIP` locally.  You can either install docker on that VM or Go.  Once that is done, invoke the Gateway using the ILB address:

```bash
$ docker run --add-host grpc.domain.com:$GW_ILB_VIP \
   -v `pwd`:/certs/ \
   -t docker.io/salrashid123/grpc_app /grpc_client \
   --host=grpc.domain.com:443 --tlsCert /certs/CA_crt.pem  \
   --servername grpc.domain.com --repeat 10

I0605 12:49:51.440915       1 grpc_client.go:104] RPC HealthChekStatus: SERVING
I0605 12:49:51.449780       1 grpc_client.go:112] RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-69787f4986-ql77m"
I0605 12:49:51.458804       1 grpc_client.go:112] RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-69787f4986-bqd9s"
I0605 12:49:51.468086       1 grpc_client.go:112] RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-69787f4986-wdhbm"
I0605 12:49:51.477872       1 grpc_client.go:112] RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-69787f4986-2v9sn"
I0605 12:49:51.486794       1 grpc_client.go:112] RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-69787f4986-mm27x"
I0605 12:49:51.495266       1 grpc_client.go:112] RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-69787f4986-dfbk7"
I0605 12:49:51.503582       1 grpc_client.go:112] RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-69787f4986-29tl7"
I0605 12:49:51.511708       1 grpc_client.go:112] RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-69787f4986-8g67x"
I0605 12:49:51.520583       1 grpc_client.go:112] RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-69787f4986-nkzqm"
I0605 12:49:51.522513       1 grpc_client.go:112] RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-69787f4986-dmszq"
```

---

Source images used in this example can be found here:
  - [docker.io/salrashid123/grpc_health_proxy](https://github.com/salrashid123/grpc_health_proxy)
  - [docker.io/salrashid123/grpc_app](https://github.com/salrashid123/grpc_health_proxy/tree/master/example)

