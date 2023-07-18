# GKE Ingress with custom default backend

This recipe provides a walk-through for setting up [GKE Ingress](https://cloud.google.com/kubernetes-engine/docs/concepts/ingress)
with custom default backend. 
When GKE Ingress deploys a load balancer, if a default backend is not specified in the Ingress manifest, GKE provides a default backend that returns 404. This is created as a `default-http-backend` NodePort service on the cluster in the` kube-system` namespace.
The 404 HTTP response is similar to the following:
```
response 404 (backend NotFound), service rules for the path non-existent
```

You can specify a custom default backend by providing a `defaultBackend` field in your Ingress manifest. Any requests that don't match the paths in the rules field are sent to the Service and port specified in the `defaultBackend` field. In this example, we demonstrate how to configure it with [Ingress for internal Application Load Balancers](../ingress-internal-basic/internal-ingress-basic.yaml), and it could be configured in the same manner for [Ingress for external Application Load Balancer](../ingress-external-basic/external-ingress-basic.yaml).

### Use-cases

- Override the default 404 server backend and route traffic to a custom catch-all page.

### Relevant documentation

- [Ingress for GKE](https://cloud.google.com/kubernetes-engine/docs/concepts/ingress)
- [GKE Ingress Default Backend](https://cloud.google.com/kubernetes-engine/docs/concepts/ingress#default_backend)
- [Ingress for Internal HTTP(S) Load Balancing](https://cloud.google.com/kubernetes-engine/docs/concepts/ingress-ilb)
- [Ingress for External HTTP(S) Load Balancing](https://cloud.google.com/kubernetes-engine/docs/concepts/ingress-xlb)

### Versions

- All supported GKE versions

### Networking Manifests

In this example, an internal Ingress resource matches for HTTP traffic with path `/foo` and sends it to the `foo` Service at port 80. Any traffic which does not match this is sent to the custom default backend service `default-be` to provide responses from custom backend.


```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: foo-internal
  annotations:
    kubernetes.io/ingress.class: "gce-internal"
spec:
  defaultBackend:
    service:
      name: default-be
      port:
        number: 80
  rules:
    - http:
        paths:
        - path: /foo
          pathType: Prefix
          backend:
            service:
              name: foo
              port:
                number: 80
```

The `foo` and `default-be` Services select across the Pods from the `foo` and `default-be` Deployment respectively, based on labels in their selector. Each Deployment consists of three Pods which will get load balanced across. Note the use of the `cloud.google.com/neg: '{"ingress": true}'` annotation. This enables container native load balancing which is a best practice. In GKE 1.17+ this is annotated by default.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: foo
  annotations:
    cloud.google.com/neg: '{"ingress": true}'
spec:
  ports:
  - port: 80
    targetPort: 8080
    name: http 
  selector:
    app: foo
  type: ClusterIP
---
apiVersion: v1
kind: Service
metadata:
  name: default-be
  annotations:
    cloud.google.com/neg: '{"ingress": true}'
spec:
  ports:
  - port: 80
    targetPort: 8080
    name: http 
  selector:
    app: default-be
  type: ClusterIP
```

### Try it out

1. Download this repo and navigate to this folder

```bash
$ git clone https://github.com/GoogleCloudPlatform/gke-networking-recipes.git
Cloning into 'gke-networking-recipes'...

$ cd gke-networking-recipes/ingress/single-cluster/ingress-custom-default-backend
```

2. Deploy the Ingress, Deployment, and Service resources in the [ingress-custom-default-backend.yaml](ingress-custom-default-backend.yaml) manifest.

```bash
$ kubectl apply -f ingress-custom-default-backend.yaml
ingress.networking.k8s.io/foo-internal created
service/foo created
service/default-be created
deployment.apps/foo created
deployment.apps/default-be created

```


3. It will take up to a minute for the Pods to deploy and up to a few minutes for the Ingress resource to be ready. Validate their progress and make sure that no errors are surfaced in the resource events.


```
$ kubectl get deployment
NAME         READY   UP-TO-DATE   AVAILABLE   AGE
default-be   3/3     3            3           76m
foo          3/3     3            3           76m

$ kubectl describe ingress foo-internal
kubectl describe ingress
Name:             foo-internal
Labels:           <none>
Namespace:        default
Address:          10.21.80.15
Ingress Class:    <none>
Default backend:  default-be:80 (10.24.0.23:8080,10.24.1.39:8080,10.24.2.31:8080)
Rules:
  Host        Path  Backends
  ----        ----  --------
  *           
              /foo   foo:80 (10.24.0.22:8080,10.24.1.38:8080,10.24.2.30:8080)
Annotations:  ingress.kubernetes.io/backends: {"k8s1-02fed221-default-default-be-80-69d4457c":"HEALTHY","k8s1-02fed221-default-foo-80-85deba71":"HEALTHY"}
              ingress.kubernetes.io/forwarding-rule: k8s2-fr-20aeohkx-default-foo-internal-jn5ch0ua
              ingress.kubernetes.io/target-proxy: k8s2-tp-20aeohkx-default-foo-internal-jn5ch0ua
              ingress.kubernetes.io/url-map: k8s2-um-20aeohkx-default-foo-internal-jn5ch0ua
              kubernetes.io/ingress.class: gce-internal
Events:
  Type    Reason  Age                 From                     Message
  ----    ------  ----                ----                     -------
  Normal  Sync    23s (x12 over 76m)  loadbalancer-controller  Scheduled for sync
```

4. Create a VM in the same VPC and the region as your GKE cluster to test the Internal Load Balancer as described in the [official documentation](https://cloud.google.com/kubernetes-engine/docs/how-to/internal-load-balance-ingress#step_5_validate_successful_ingress_deployment).

As an example, assuming you already have a Firewall Rule to allow SSH for instances with the "allow-ssh" tag:

```bash
gcloud compute instances create l7-ilb-client \
--image-family=debian-9 \
--image-project=debian-cloud \
--network=<YOUR_VPC> \
--subnet=<YOUR_SUBNET> \
--zone=us-<YOUR_REGION> \
--tags=allow-ssh
```

5. Finally, we can validate the data plane by sending traffic to our Ingress VIP from this VM we created in step 4.

```bash
# SSH into the test VM
$  gcloud compute ssh l7-ilb-client \
--zone=<YOUR_ZONE>
# Using curl from the test VM to the Internal Ingress VIP
$ curl 10.21.80.15/foo
{"cluster_name":"gke-1","host_header":"10.21.80.16","pod_name":"foo-65db7dbbbb-d2csd","pod_name_emoji":"\ud83c\ude39","project_id":"<PROJECT ID>","zone":"us-west1-a"}

curl 10.21.80.15/bar
{"cluster_name":"gke-1","host_header":"10.21.80.16","pod_name":"default-be-68588dd84f-gklts","pod_name_emoji":"\ud83d\udc68\ud83c\udffc\u200d\ud83e\uddb2","project_id":"<PROJECT ID>","zone":"us-west1-a"}
```

You should be able to see that requests with path `/foo` being routed to `foo` service(to pods with foo...), whereas other requests being routed to `default-be` service(to pods with default-be...).

### Cleanup

```bash
kubectl delete -f ingress-custom-default-backend.yaml
```

Deleting the test VM created in step 4:

```bash
gcloud compute instances delete l7-ilb-client --zone <YOUR_ZONE>
```
