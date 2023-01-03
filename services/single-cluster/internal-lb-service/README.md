# Internal Load Balancer Service

Internal Load Balancing on GKE deploys an internal TCP/UDP load balancer for private L4 load balancing. This example deploys an application on GKE and exposes the application with a private load balanced IP address. See the [internal-lb-service.yaml](internal-lb-service.yaml) manifest for the full deployment spec.

### Use-cases

- Private exposure of a GKE internal application
- TCP or UDP Load Balancing for private Services

### Relevant documentation

- [Services of type LoadBalancer](https://cloud.google.com/kubernetes-engine/docs/concepts/service#services_of_type_loadbalancer).  **Note:** an annotation is required to ensure an internal LB is created and not an external LB.
- [Creating an internal TCP load balancer Service](https://cloud.google.com/kubernetes-engine/docs/how-to/internal-load-balancing#create)
- [Optional alternative subnet for GKE internal load balancers](https://cloud.google.com/kubernetes-engine/docs/how-to/internal-load-balancing#lb_subnet)

### Versions

- All supported GKE versions


![internal LoadBalancer service](../../../images/internal-lb-service.png)

### Networking Manifests

In this example, a Service matches TCP traffic destined to port 80 and load balances across pods in the `foo` Deployment on TCP port 8080.  Key aspects of this manifest include:

- The `type: LoadBalancer` specification and the metadata annotation `cloud.google.com/load-balancer-type: "Internal"` that prompt GKE to create an internal TCP/UDP Load Balancer for this Service
- The `spec.ports.port` to define the port that the internal load balancer will listen on, whereas the `spec.ports.targetPort` defines the port that the pods in the Deployment will listen on.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: foo
  annotations:
    cloud.google.com/load-balancer-type: "Internal"
  labels:
    app: foo
spec:
  ports:
  - port: 80
    targetPort: 8080
    protocol: TCP
  selector:
    app: foo
  type: LoadBalancer
```


### Try it out

1. Download this repo and navigate to this folder.

```bash
$ git clone https://github.com/GoogleCloudPlatform/gke-networking-recipes.git
Cloning into 'gke-networking-recipes'...

$ cd gke-networking-recipes/internal-lb-service
```

2. Deploy the Deployment and Service resources in the [internal-lb-service.yaml](internal-lb-service.yaml) manifest.

```bash
$ kubectl apply -f internal-lb-service.yaml
service/foo created
deployment.apps/foo created
```

3. It may take up to a minute for the pods to deploy and up to a few minutes for the internal IP address of the Service resource to be ready. Validate the progress and make sure that no errors are surfaced in the resource events. [Google Cloud health checks](https://cloud.google.com/load-balancing/docs/health-check-concepts#ip-ranges) are created within your VPC by the GKE Service controller so that health checks are allowed to reach your cluster. If the load balancer health checks appear to not be passing, check that the correct VPC firewall rules are installed.

```bash
$ kubectl get deploy foo
NAME   READY   UP-TO-DATE   AVAILABLE   AGE
foo    3/3     3            3           20s

$ kubectl describe svc foo
Name:                     foo
Namespace:                default
Labels:                   app=foo
Annotations:              cloud.google.com/load-balancer-type: Internal
                          kubectl.kubernetes.io/last-applied-configuration:
                           {"apiVersion":"v1","kind":"Service","metadata":{"annotations":{"cloud.google.com/load-balancer-type":"Internal"},"labels":{"app":"foo"},\"n...
Selector:                 app=foo
Type:                     LoadBalancer
IP:                       10.4.9.249
LoadBalancer Ingress:     10.138.0.31
Port:                     <unset>  80/TCP
TargetPort:               8080/TCP
NodePort:                 <unset>  31153/TCP
Endpoints:                10.0.0.6:8080,10.0.1.6:8080,10.0.2.7:8080
Session Affinity:         None
External Traffic Policy:  Cluster
Events:
  Type    Reason                Age   From                Message
  ----    ------                ----  ----                -------
  Normal  EnsuringLoadBalancer  55s   service-controller  Ensuring load balancer
  Normal  EnsuredLoadBalancer   4s    service-controller  Ensured load balancer

```


4. Create or use an existing VM in the same VPC and region as your GKE cluster to test the Internal Load Balancer.

As an example, assuming there is already a Firewall Rule to allow SSH for instances with the "allow-ssh" tag, you can create a test VM:

```bash
$ gcloud compute instances create l4-ilb-client \
--image-family=debian-9 \
--image-project=debian-cloud \
--network=<YOUR_VPC> \
--subnet=<YOUR_SUBNET> \
--zone=us-<YOUR_REGION> \
--tags=allow-ssh
```

5. Finally, validate the data plane by sending traffic to the VIP from the VM created in step 4.

```bash
# SSH into the test VM
$  gcloud compute ssh l4-ilb-client \
--zone=<YOUR_ZONE>
# Using curl from the test VM to the LoadBalancer Ingress IP
$ curl 10.138.0.31
{"cluster_name":"gke-1","host_header":"10.138.0.31","node_name":"gke-gke-1-default-pool-f8833294-vxnd.c.cythom-sandbox-001.internal","pod_name":"foo-66d75b5644-w9tkc","pod_name_emoji":"🍫","project_id":"cythom-sandbox-001","timestamp":"2020-11-14T03:18:56","zone":"us-west1-a"}
```

### Cleanup

Delete the GKE internal load balancer:

```bash
kubectl delete -f internal-lb-service.yaml
```

and delete the test VM created in step 4:

```bash
gcloud compute instances delete l4-ilb-client --zone <YOUR_ZONE>
```
