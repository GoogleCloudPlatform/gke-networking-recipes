
# GKE Ingress + NGNIX Ingress

GKE allows customers to deploy their own Ingress Controllers instead of the standard GCP offering. NGNIX is a popular option because of it's simplicity and open source nature. This example deploys an application on GKE and exposes the application with an NGNIX controller. See the [ingress-ngnix.yaml](./ingress-nginx.yaml) manifest for full deployment spec. 

### Use-cases

- Load Balance Websocket and HTTPS applications
- Rewrite request URIs before sending it to an application

### Relevant documentation

- [Ingress for GKE](https://cloud.google.com/kubernetes-engine/docs/concepts/ingress)
- [Ingress with NGINX](https://cloud.google.com/community/tutorials/nginx-ingress-gke)
- [NGNIX on GKE](https://kubernetes.github.io/ingress-nginx/deploy/#gce-gke)

### Versions

- 1.16.5-gke.1 and later.


## Note
NGINX is not one of the GKE offering, this is just an exmaple of using custom controller.

### Networking Manifests

In this example an external Ingress resource matches for HTTP traffic with `foo.example.com`  for path `/foo`  and sends it to the `foo` Service at port 8080. A public IP address is automatically provisioned by the Ngnix controller which listens for traffic on port 8080. The Ingress resource below shows that there is one host match. Any traffic which does not match this is sent to the default backend to provide 404 responses.


```yaml
apiVersion:  networking.k8s.io/v1
kind: Ingress
metadata:
  name: foo-external
  annotations:
    kubernetes.io/ingress.class: "nginx"
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
spec:
  rules:
  - host: foo.example.com
    http:
      paths:
      - path: /foo
        pathType: Prefix
        backend:
          service:
            name: foo
            port:
              number: 8080
```

The following `foo` Service selects across the Pods from the `foo` Deployment. This Deployment consists of three Pods which will get load balanced across.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: foo
spec:
  ports:
  - port: 80
    targetPort: 8080
    name: http
  selector:
    app: foo
  type: ClusterIP
```

### Try it out

1. Download this repo and navigate to this folder

```bash
$ git clone https://github.com/GoogleCloudPlatform/gke-networking-recipes.git
Cloning into 'gke-networking-recipes'...

$ cd gke-networking-recipes/ingress/single-cluster/ingress-ngnix
```
2. Ensure that your user has cluster-admin permissions on the cluster. This can be done with the following command:

```
kubectl create clusterrolebinding cluster-admin-binding \
  --clusterrole cluster-admin \
  --user $(gcloud config get-value account)
```
3. Install the ingress controller 

```
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.1.0/deploy/static/provider/cloud/deploy.yaml
```

4. Deploy the Ingress, Deployment, and Service resources in the [ingress-ngnix.yaml](./ingress-nginx.yaml) manifest.

```bash
$ kubectl apply -f ingress-nginx.yaml
ingress.networking.k8s.io/ingress-resource created
service/foo created
deployment.apps/foo created

```


5. It will take up to a minute for the Pods to deploy and up to a few minutes for the Ingress resource to be ready. Validate their progress and make sure that no errors are surfaced in the resource events.


```
$ kubectl get deploy foo
NAME   READY   UP-TO-DATE   AVAILABLE   AGE
foo    3/3     3            3           2m56s

$ kubectl describe ingress ingress-resource
Name:             ingress-resource
Namespace:        default
Address:          34.102.236.246
Default backend:  default-http-backend:80 (10.96.0.5:8080)
Rules:
  Host             Path  Backends
  ----             ----  --------
  foo.example.com
                   /foo   foo:8080 (10.96.1.3:8080,10.96.1.4:8080,10.96.2.5:8080)
Annotations:       kubernetes.io/ingress.class: nginx
                   nginx.ingress.kubernetes.io/ssl-redirect: false
Events:            <none>
```

Please note in the event logs that some firewall rules should be manually configured for health checks.

6. Finally, we can validate the data plane by sending traffic to our Ingress VIP

```bash

$ curl -H "host: foo.example.com" 34.102.236.246/foo

```

### Cleanup

```bash
kubectl delete -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.1.0/deploy/static/provider/cloud/deploy.yaml
kubectl delete -f ingress-nginx.yaml
```