### Example GKE Deployment

For an end-to-end example of gRPC Loadbalancing with gRPC:

First deploy a GKE cluster with NEG enabled:

```bash
$ gcloud container  clusters create cluster-1 --machine-type "n1-standard-2" 
  --zone us-central1-a  --num-nodes 2 --enable-ip-alias  \
  --cluster-version "1.19"  -q
```

Deploy application

```bash
kubectl apply -f .
```

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
```


#### Test External

Verify external loadbalancing by transmitting 10 RPCs over one channel.  The responses will show different pods that handled each request

```log
$ docker run --add-host grpc.domain.com:34.120.140.72  \
  -t gcr.io/cloud-solutions-images/grpc_app /grpc_client \
   --host=grpc.domain.com:443 --tlsCert /certs/CA_crt.pem \
   --servername grpc.domain.com --repeat 10

2021/01/27 12:53:08 RPC HealthChekStatus:SERVING
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
$ docker run --add-host grpc.domain.com:34.120.140.72 \
   -t gcr.io/cloud-solutions-images/grpc_app /grpc_client \
   --host=grpc.domain.com:443 --tlsCert /certs/CA_crt.pem  \
   --servername grpc.domain.com --repeat 10

2021/01/27 12:54:18 RPC HealthChekStatus:SERVING
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

To test the internal loadbalancer, you must configure a VM from within an [allocated network](https://cloud.google.com/load-balancing/docs/l7-internal/setting-up-l7-internal#configuring_the_proxy-only_subnet)

```log
 $ docker run --add-host grpc.domain.com:10.128.0.77 \
     -t gcr.io/cloud-solutions-images/grpc_app /grpc_client \
     --host=grpc.domain.com:443 --tlsCert /certs/CA_crt.pem  \
     --servername grpc.domain.com --repeat 10

2021/01/27 12:51:45 RPC HealthChekStatus:SERVING
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

Source images used in this example can be found here:
  - [gcr.io/cloud-solutions-images/grpc_health_proxy](https://github.com/salrashid123/grpc_health_proxy)
  - [gcr.io/cloud-solutions-images/grpc_app](https://github.com/salrashid123/grpc_health_proxy/tree/master/example)