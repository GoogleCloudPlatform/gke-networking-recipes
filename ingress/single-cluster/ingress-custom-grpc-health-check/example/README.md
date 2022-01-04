### Example GKE Deployment

For an end-to-end example of gRPC Load Balancing with gRPC:

First deploy a GKE cluster with NEG enabled:

```bash
$ gcloud container  clusters create cluster-1 \
  --machine-type "n1-standard-2" \
  --zone us-central1-a  --num-nodes 2 --enable-ip-alias  -q
```

Configure a custom SSL Policy (this is optional and simply added to demonstrate custom TLS policies using `networking.gke.io/v1beta1.FrontEndConfig`)

```
gcloud compute ssl-policies create gke-ingress-ssl-policy \
    --profile MODERN \
    --min-tls-version 1.2 
```

Deploy application

```bash
kubectl apply -f .
```

> Please note the deployments here use the health_check proxy and sample gRPC applications hosted on `docker.io/`.  You can build and deploy these images into your own repository as well.

Wait ~8mins and note down the external and ILB addresses

```bash
$ kubectl get po,svc,ing
NAME                                READY   STATUS    RESTARTS   AGE
pod/fe-deployment-6c96c9648-sztpp   2/2     Running   0          112s
pod/fe-deployment-6c96c9648-zj659   2/2     Running   0          119s

NAME                     TYPE        CLUSTER-IP    EXTERNAL-IP   PORT(S)     AGE
service/fe-srv-ingress   ClusterIP   10.10.44.25   <none>        50051/TCP   3m
service/kubernetes       ClusterIP   10.10.32.1    <none>        443/TCP     4d9h

NAME                                       CLASS    HOSTS   ADDRESS         PORTS     AGE
ingress.networking.k8s.io/fe-ilb-ingress   <none>   *       10.128.0.77     80, 443   3m1s
ingress.networking.k8s.io/fe-ingress       <none>   *       34.120.140.72   80, 443   3m1s

export XLB_IP=`kubectl get ingress.extensions/fe-ingress -o jsonpath='{.status.loadBalancer.ingress[].ip}'`
export ILB_IP=`kubectl get ingress.extensions/fe-ilb-ingress -o jsonpath='{.status.loadBalancer.ingress[].ip}'`

echo $XLB_IP
echo $ILB_IP
```

NOTE:
- [Configuring Ingress for external load balancing](https://cloud.google.com/kubernetes-engine/docs/how-to/load-balance-ingress#creating_an_ingress)
 >> The only supported path types for the pathType field is ImplementationSpecific.
#### Test External

Verify external loadbalancing by transmitting 10 RPCs over one channel.  The responses will show different pods that handled each request

```log
$ docker run --add-host grpc.domain.com:$XLB_IP  \
  -t docker.io/salrashid123/grpc_app /grpc_client \
   --host=grpc.domain.com:443 --tlsCert /certs/CA_crt.pem \
   --servername grpc.domain.com --repeat 10 -skipHealthCheck

2021/01/27 12:53:08 RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-6c96c9648-sztpp"
2021/01/27 12:53:08 RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-6c96c9648-zj659"
2021/01/27 12:53:08 RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-6c96c9648-zj659"
2021/01/27 12:53:09 RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-6c96c9648-sztpp"
2021/01/27 12:53:09 RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-6c96c9648-zj659"
2021/01/27 12:53:09 RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-6c96c9648-sztpp"
2021/01/27 12:53:09 RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-6c96c9648-zj659"
2021/01/27 12:53:09 RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-6c96c9648-zj659"
2021/01/27 12:53:09 RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-6c96c9648-sztpp"
2021/01/27 12:53:09 RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-6c96c9648-zj659"
```

Now scale the number of pods

```bash
$ kubectl scale --replicas=10 deployment.apps/fe-deployment
```

```bash
$ kubectl get po
NAME                            READY   STATUS    RESTARTS   AGE
fe-deployment-6c96c9648-2c9vv   2/2     Running   0          18s
fe-deployment-6c96c9648-9p7q9   2/2     Running   0          18s
fe-deployment-6c96c9648-d4rx2   2/2     Running   0          18s
fe-deployment-6c96c9648-gpjvg   2/2     Running   0          18s
fe-deployment-6c96c9648-h7p2c   2/2     Running   0          18s
fe-deployment-6c96c9648-s9tl2   2/2     Running   0          18s
fe-deployment-6c96c9648-sztpp   2/2     Running   0          4m32s
fe-deployment-6c96c9648-tmmwd   2/2     Running   0          18s
fe-deployment-6c96c9648-xc7d7   2/2     Running   0          18s
fe-deployment-6c96c9648-zj659   2/2     Running   0          4m39s
```

Rerun the test.  Notice the new pods in the response 
```log
$ docker run --add-host grpc.domain.com:$XLB_IP \
   -t docker.io/salrashid123/grpc_app /grpc_client \
   --host=grpc.domain.com:443 --tlsCert /certs/CA_crt.pem  \
   --servername grpc.domain.com --repeat 10 -skipHealthCheck

2021/01/27 12:54:19 RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-6c96c9648-sztpp"
2021/01/27 12:54:19 RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-6c96c9648-xc7d7"
2021/01/27 12:54:19 RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-6c96c9648-d4rx2"
2021/01/27 12:54:19 RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-6c96c9648-s9tl2"
2021/01/27 12:54:19 RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-6c96c9648-2c9vv"
2021/01/27 12:54:19 RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-6c96c9648-zj659"
2021/01/27 12:54:19 RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-6c96c9648-sztpp"
2021/01/27 12:54:19 RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-6c96c9648-sztpp"
2021/01/27 12:54:19 RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-6c96c9648-h7p2c"
2021/01/27 12:54:19 RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-6c96c9648-sztpp"
```

#### Test Internal

To test the internal loadbalancer, you must configure a VM from within an [allocated network](https://cloud.google.com/load-balancing/docs/l7-internal/setting-up-l7-internal#configuring_the_proxy-only_subnet) and export the environment variable `$XLB_IP` locally

```log
 $ docker run --add-host grpc.domain.com:$XLB_IP \
     -t docker.io/salrashid123/grpc_app /grpc_client \
     --host=grpc.domain.com:443 --tlsCert /certs/CA_crt.pem  \
     --servername grpc.domain.com --repeat 10 -skipHealthCheck

2021/01/27 12:51:45 RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-6c96c9648-sztpp"
2021/01/27 12:51:45 RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-6c96c9648-zj659"
2021/01/27 12:51:45 RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-6c96c9648-sztpp"
2021/01/27 12:51:45 RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-6c96c9648-zj659"
2021/01/27 12:51:45 RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-6c96c9648-sztpp"
2021/01/27 12:51:45 RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-6c96c9648-zj659"
2021/01/27 12:51:45 RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-6c96c9648-sztpp"
2021/01/27 12:51:45 RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-6c96c9648-zj659"
2021/01/27 12:51:45 RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-6c96c9648-sztpp"
2021/01/27 12:51:45 RPC Response: message:"Hello unary RPC msg   from hostname fe-deployment-6c96c9648-zj659"
```

### HTTP/2 HealthChecks

If you want the healthCheck proxy to use HTTP/2, you need to enable TLS termination on the proxy.  To do that, mount TLS certificates to the pod and configure the proxy to use them:

e.g.

```yaml
apiVersion: v1
data:
  http_server_crt.pem: LS0tLS1CRUdJTiBDRVJ-redacted
  http_server_key.pem: LS0tLS1CRUdJTiBQUkl-redacted
kind: Secret
metadata:
  name: hc-secret
  namespace: default
type: Opaque
---
```

- `fe-deployment.yaml`:

```yaml
    spec:
      containers:
      - name: hc-proxy
        image: docker.io/salrashid123/grpc_health_proxy:1.0.0
        args: [
          "--http-listen-addr=0.0.0.0:8443",
          "--grpcaddr=localhost:50051",
          "--service-name=echo.EchoServer",
          "--https-listen-ca=/config/CA_crt.pem",
          "--https-listen-cert=/certs/http_server_crt.pem",
          "--https-listen-key=/certs/http_server_key.pem",
          "--grpctls",        
          "--grpc-sni-server-name=grpc.domain.com",
          "--grpc-ca-cert=/config/CA_crt.pem",
          "--logtostderr=1",
          "-v=1"
        ]
        ports:
        - containerPort: 8443
        volumeMounts:
        - name: certs-vol
          mountPath: /certs
          readOnly: true
      volumes:
      - name: certs-vol
        secret:
          secretName: hc-secret          
```

You will also need to configure the service to use HTTP/2,  please make sure the healthproxy listens over TLS

- `fe-srv-ingress.yaml`

```yaml
apiVersion: cloud.google.com/v1
kind: BackendConfig
metadata:
  name: fe-grpc-backendconfig
spec:
  healthCheck:
    type: HTTP2
    requestPath: /
    port: 8443
```

Source images used in this example can be found here:
  - [docker.io/salrashid123/grpc_health_proxy](https://github.com/salrashid123/grpc_health_proxy)
  - [docker.io/salrashid123/grpc_app](https://github.com/salrashid123/grpc_health_proxy/tree/master/example)