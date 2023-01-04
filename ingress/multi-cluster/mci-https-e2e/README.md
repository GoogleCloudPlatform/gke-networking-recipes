# MultiCluster Ingress with end to end https

[Multi-cluster Ingress](https://cloud.google.com/kubernetes-engine/docs/concepts/ingress-for-anthos) for GKE is a cloud-hosted Ingress controller for GKE clusters. It's a Google-hosted service that supports deploying shared load balancing resources across clusters and across regions.

[Multi-cluster service](https://cloud.google.com/kubernetes-engine/docs/concepts/multi-cluster-ingress#multiclusterservice_resources) is a Google developed [CRD](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/) (Custom Resource Definition) for GKE. MCS is a custom resource used by Multi Cluster Ingress that is a logical representation of a Service across multiple clusters. It also allows to use [HTTPS backends](hhttps://cloud.google.com/kubernetes-engine/docs/how-to/multi-cluster-ingress#application_protocols) with MCI.

## Use-cases

- Encrypted traffic between both clients and HTTPS load balancer on one side and the load balancer and the backend pods on the other side.
- Disaster recovery for internet traffic across clusters or regions.
- Low-latency serving of traffic to globally distributed GKE clusters.

## Relevant documentation

- [Multi-cluster Ingress Concepts](https://cloud.google.com/kubernetes-engine/docs/concepts/ingress-for-anthos)
- [Setting Up Multi-cluster Ingress](https://cloud.google.com/kubernetes-engine/docs/how-to/ingress-for-anthos-setup)
- [Deploying Ingress Across Clusters](https://cloud.google.com/kubernetes-engine/docs/how-to/ingress-for-anthos)
- [Google Cloud External HTTP(S) Load Balancing](https://cloud.google.com/load-balancing/docs/https)
- [BackendConfig CRD](https://cloud.google.com/kubernetes-engine/docs/how-to/ingress-features#configuring_ingress_features_through_backendconfig_parameters)

## Versions

- GKE clusters on GCP
- All versions of GKE supported
- Tested and validated with 1.20.10-gke.1600 on Nov 23th 2021

### Networking Manifests

This recipe demonstrates deploying Multi-cluster Ingress across two clusters to expose two different Services hosted across both clusters. The cluster `gke-1` is in `REGION#1` and `gke-2` is hosted in `REGION#2`, demonstrating multi-regional load balancing across clusters. All Services will share the same MultiClusterIngress and load balancer IP, but the load balancer will match traffic and send it to the right region, cluster, and Service depending on the request.

[//]: # (TODO - Missing diagram https://github.com/GoogleCloudPlatform/gke-networking-recipes/issues/119)

This Recipes also demonstrates the following:

- How to enable HTTPS on Multi-cluster Ingress.
- How to use HTTPS backends with Multi-cluster Igress for end to end encryption.

There are two applications in this example, `foo` and `bar` Deployed on both clusters. The External HTTPS load balancer is designed to route traffic to the closest (to the client) available backend with capacity. Traffic from clients will be load balanced to the closest backend cluster depending on the traffic matching specified in the MultiClusterIngress resource.

The two clusters in this example can be backends to MCI only if they are registered through Hub. Hub is a central registry of clusters that determines which clusters MCI can function across. A cluster must first be registered to Hub before it can be used with MCI.

There are two Custom Resources (CRs) that control multi-cluster load balancing - the MultiClusterIngress (MCI) and the MultiClusterService (MCS). The MCI below describes the desired traffic matching and routing behavior. Similar to an Ingress resource, it can specify host and path matching with Services. This MCI specifies two host rules and a default backend which will receive all traffic that does not have a match. The `serviceName` field in this MCI specifies the name of an MCS resource.

The MCI below also defines via annotations:

- A [Google-Managed Certificate](https://cloud.google.com/kubernetes-engine/docs/how-to/multi-cluster-ingress#google-managed_certificates)
- A public [Static IP](https://cloud.google.com/compute/docs/ip-addresses/reserve-static-external-ip-address) used to provision Google-Managed Certificates

```yaml
apiVersion: networking.gke.io/v1
kind: MultiClusterIngress
metadata:
  name: foobar-ingress
  namespace: multi-cluster-demo
  annotations:
    networking.gke.io/static-ip: 34.149.198.76
    networking.gke.io/pre-shared-certs: "mci-certs"
spec:
  template:
    spec:
      backend:
        serviceName: default-backend
        servicePort: 443
      rules:
      - host: bar.endpoints.$PROJECT-ID.cloud.goog
        http:
          paths:
            - backend:
                serviceName: bar
                servicePort: 443
      - host: foo.endpoints.$PROJECT-ID.cloud.goog
        http:
          paths:
            - backend:
                serviceName: foo
                servicePort: 443
```

Similar to the Kubernetes Service, the MultiClusterService (MCS) describes label selectors and other backend parameters to group pods in the desired way. This ```foo``` MCS specifies that all Pods with the following characteristics will be selected as backends for ```foo```::

- Pods with the label `app: foo`
- In the `multi-cluster-demo` Namespace
- In any of the clusters that are registered as members to the Hub

The MCS below also defines via annotations:

- A [Backend Health Check](https://cloud.google.com/kubernetes-engine/docs/how-to/ingress-features#direct_health) through backendconfig CRD
- Backend protocol as [HTTPS](https://cloud.google.com/kubernetes-engine/docs/how-to/multi-cluster-ingress#application_protocols)

```yaml
apiVersion: networking.gke.io/v1
kind: MultiClusterService
metadata:
  name: bar
  namespace: multi-cluster-demo
  annotations:
    beta.cloud.google.com/backend-config: '{"ports": {"443":"backend-health-check"}}'
    networking.gke.io/app-protocols: '{"https":"HTTPS"}'
spec:
  template:
    spec:
      selector:
        app: foo
      ports:
      - name: https
        protocol: TCP
        port: 443
        targetPort: 443
```

Each of the three MCS's referenced in the ```foobar-ingress``` MCI have their own manifest to describe the matching parameters of that MCS. A BackendConfig resource is also referenced. This allows settings specific to a Service to be configured. We use it here to configure the health check that the Google Cloud load balancer uses.

```yaml
apiVersion: cloud.google.com/v1
kind: BackendConfig
metadata:
  name: backend-health-check
  namespace: multi-cluster-demo
spec:
  healthCheck:
    requestPath: /healthz
    port: 443
    type: HTTPS
```

If more clusters are added to the Hub, then any Pods in those clusters that match these characteristics will also be registered as backends to `bar`.

### Cloud Endpoints DNS

To create a stable, human-friendly mapping to your Ingress IP, you must have a public DNS record. You can use any DNS provider and automation that you want. This recipe uses Endpoints instead of creating a managed DNS zone. Endpoints provides a free Google-managed DNS record for a public IP.

NB: we use Cloud Endpoints DNS for the purposes of demonstration. This services has some limitations, most notabley when you register an endpoint and delete it you cannot reuse the same name for 30 days. You will have to use a new names if you register/unregister endpoints quickly.

```yaml
swagger: "2.0"
info:
  description: "Cloud Endpoints DNS"
  title: "Cloud Endpoints DNS"
  version: "1.0.0"
paths: {}
host: "bar.endpoints.$PROJECT-ID.cloud.goog"
x-google-endpoints:
- name: "bar.endpoints.$PROJECT-ID.cloud.goog"
  target: "$GCLB_IP"
```

Now that you have the background knowledge and understanding of MCI, you can try it out yourself.

## Try it out

1. Download this repo and navigate to this folder

    ```bash
    git clone https://github.com/GoogleCloudPlatform/gke-networking-recipes.git
    Cloning into 'gke-networking-recipes'...

    cd gke-networking-recipes/ingress/multi-cluster/mci-https-e2e
    ```

2. Set up Environment variables

    ```bash
    export PROJECT=$(gcloud config get-value project) # or your preferred project
    export GKE1_ZONE=GCP_CLOUD_ZONE # Pick a supported Zone for cluster gke-1
    export GKE2_ZONE=GCP_CLOUD_ZONE # Pick a supported Zone for cluster gke-2
    ```

    NB: This tutorial uses Zonal Clusters, you can also use Regional Clusters. Replace a Zone with a region and use the ```--region``` flag instead of ```--zone``` in the next steps

3. Deploy the two clusters `gke-1` and `gke-2` as specified in [cluster setup](../../../cluster-setup.md#multi-cluster-environment-basic). Once done, come back to the next step.

4. Create a Static IP for the load balancer and register it to DNS

    In order to use Google-Managed Certificated, a static IP needs to be reserved and registered with your DNS Server.

    Start by creating a public Static IP.

    ```bash
    gcloud compute addresses create mci-address --global
    ```

    Get the reserved IP.

    ```bash
    gcloud compute addresses list
    ```

5. Edit the ```dns-spec-foo.yaml``` and ```dns-spec-bar.yaml``` files and update ```$PROJECT-ID``` value with your project id and ```$GCLB_IP``` with public IP that was created to create Endpoints.

6. Deploy the Cloud Endpoints DNS specs file in your Cloud project:  
    The YAML specification defines the public DNS record in the form of bar.endpoints.PROJECT-ID.cloud.goog, where PROJECT-ID is your unique project number.

    ```bash
    gcloud endpoints services deploy dns-spec-foo.yaml
    gcloud endpoints services deploy dns-spec-bar.yaml
    ```

7. Provision Google-Managed Certificates

    We will use Google-Managed Certificates in this example to provision and HTTPS LoadBalancer, run the following command.

    ```bash
    gcloud compute ssl-certificates create mci-certs --domains=foo.endpoints.${PROJECT}.cloud.goog,bar.endpoints.${PROJECT}.cloud.goog --global
    ```

    Check that the certificates have been created

    ```bash
    gcloud compute ssl-certificates list
    ```

    The MANAGED_STATUS will indicate ```PROVISIONNING```. This is normal, the certificates will be provisionned when you deploy the MCI

8. We are using a HAPROXY sidecar ```(container image: haproxytech/haproxy-alpine:2.4)``` for HTTPS backend. The backend [SSL terminates](https://www.haproxy.com/blog/haproxy-ssl-termination/) at HAPROXY.

   The `haproxy` directory in this code repository has a sample config file for HAPROXY. Change to this directory for steps 8 and 9.

   Create self-signed certificate for backends using openssl

    ```bash
    mkdir certs
    openssl req -newkey rsa:2048 -nodes -keyout certs/key.pem -x509 -days 365 -out certs/certificate.pem
    ```

   Provide required inputs when prompted by above command. Once key and certificate are generated successfully, create a a file that contains both certificate and the private key.

    ```bash
    cat certs/certificate.pem certs/key.pem >> certs/mycert.pem
    rm certs/certificate.pem certs/key.pem
    ```

9. Log in to each cluster and create namespace

    ```bash
    kubectl --context=gke-1 create namespace multi-cluster-demo
    kubectl --context=gke-2 create namespace multi-cluster-demo
    ```

10. Log in to each cluster and create secret for self-signed certificate

     ```bash
     kubectl --context=gke-1 create secret generic haproxy-cert --from-file=certs/mycert.pem -n multi-cluster-demo
     kubectl --context=gke-2 create secret generic haproxy-cert --from-file=certs/mycert.pem -n multi-cluster-demo
     ```

11. Log in to each cluster and create config map for HA Proxy sidecar

     ```bash
     kubectl --context=gke-1 create configmap haproxy-config --from-file=haproxy.cfg -n multi-cluster-demo
     kubectl --context=gke-2 create configmap haproxy-config --from-file=haproxy.cfg -n multi-cluster-demo
     ```

12. Log in to each cluster and deploy the app.yaml manifest.

     ```bash
    kubectl --context=gke-1 apply -f app.yaml
    kubectl --context=gke-2 apply -f app.yaml
    ```

13. Edit the ```ingress.yaml``` file and update:

    ```networking.gke.io/static-ip``` value with the IP address you reserved earlier.
    ```$PROJECT-ID``` with your project id.

14. The multi-cluster service resource should have `networking.gke.io/app-protocols` annotation for HTTPS backends.

15. Now log into `gke-1` and deploy the ingress.yaml manifest.

    ```bash
    kubectl --context=gke-1 apply -f ingress.yaml
    ```

16. It can take up to 10 minutes for the load balancer to deploy fully. Inspect the MCI resource to watch for events that indicate how the deployment is going. Then capture the IP address for the MCI ingress resource.

    ```bash
    kubectl --context=gke-1 describe mci/foobar-ingress -n multi-cluster-demo
    Name:         foobar-ingress
    Namespace:    multi-cluster-demo
    Labels:       <none>
    Annotations:  networking.gke.io/pre-shared-certs: mci-certs
                  networking.gke.io/static-ip: x.x.x.x
    API Version:  networking.gke.io/v1
    Kind:         MultiClusterIngress
    Metadata:
      Creation Timestamp:  2023-01-04T12:34:03Z
      Finalizers:
        mci.finalizer.networking.gke.io
      Generation:  1
      Managed Fields:
        API Version:  networking.gke.io/v1
        Fields Type:  FieldsV1
        fieldsV1:
          f:metadata:
            f:annotations:
              .:
              f:kubectl.kubernetes.io/last-applied-configuration:
              f:networking.gke.io/pre-shared-certs:
              f:networking.gke.io/static-ip:
          f:spec:
            .:
            f:template:
              .:
              f:spec:
                .:
                f:backend:
                  .:
                  f:serviceName:
                  f:servicePort:
                f:rules:
        Manager:      kubectl-client-side-apply
        Operation:    Update
        Time:         2023-01-04T12:34:03Z
        API Version:  networking.gke.io/v1beta1
        Fields Type:  FieldsV1
        fieldsV1:
          f:metadata:
            f:finalizers:
              .:
              v:"mci.finalizer.networking.gke.io":
        Manager:         Google-Multi-Cluster-Ingress
        Operation:       Update
        Time:            2023-01-04T12:34:04Z
      Resource Version:  1064930
      UID:               76d0e817-be0b-4b80-b286-8093b6e57ba2
    Spec:
      Template:
        Spec:
          Backend:
            Service Name:  default-backend
            Service Port:  443
          Rules:
            Host:  bar.endpoints.$PROJECT-ID.cloud.goog
            Http:
              Paths:
                Backend:
                  Service Name:  bar
                  Service Port:  443
            Host:                foo.endpoints.$PROJECT-ID.cloud.goog
            Http:
              Paths:
                Backend:
                  Service Name:  foo
                  Service Port:  443
    Events:
      Type    Reason  Age   From                              Message
      ----    ------  ----  ----                              -------
      Normal  ADD     18s   multi-cluster-ingress-controller  multi-cluster-demo/foobar-ingress
      Normal  UPDATE  17s   multi-cluster-ingress-controller  multi-cluster-demo/foobar-ingress
    ```

17. Now use the hosts defined in the MCI to reach the load balancer.

    ```bash
    curl -v -L https://foo.endpoints.$PROJECT-ID.cloud.goog
    *   Trying x.x.x.x:443...
    * Connected to foo.endpoints.$PROJECT-ID.cloud.goog (x.x.x.x) port 443 (#0)
    * ALPN, offering h2
    * ALPN, offering http/1.1
    * successfully set certificate verify locations:
    *  CAfile: /etc/ssl/cert.pem
    *  CApath: none
    * TLSv1.2 (OUT), TLS handshake, Client hello (1):
    * TLSv1.2 (IN), TLS handshake, Server hello (2):
    * TLSv1.2 (IN), TLS handshake, Certificate (11):
    * TLSv1.2 (IN), TLS handshake, Server key exchange (12):
    * TLSv1.2 (IN), TLS handshake, Server finished (14):
    * TLSv1.2 (OUT), TLS handshake, Client key exchange (16):
    * TLSv1.2 (OUT), TLS change cipher, Change cipher spec (1):
    * TLSv1.2 (OUT), TLS handshake, Finished (20):
    * TLSv1.2 (IN), TLS change cipher, Change cipher spec (1):
    * TLSv1.2 (IN), TLS handshake, Finished (20):
    * SSL connection using TLSv1.2 / ECDHE-RSA-CHACHA20-POLY1305
    * ALPN, server accepted to use h2
    * Server certificate:
    *  subject: CN=foo.$DOMAIN
    *  start date: Nov  2 09:26:04 2021 GMT
    *  expire date: Jan 31 09:26:03 2022 GMT
    *  subjectAltName: host "foo.$DOMAIN" matched cert's "foo.$DOMAIN"
    *  issuer: C=US; O=Google Trust Services LLC; CN=GTS CA 1D4
    *  SSL certificate verify ok.
    * Using HTTP2, server supports multi-use
    * Connection state changed (HTTP/2 confirmed)
    * Copying HTTP/2 data in stream buffer to connection buffer after upgrade: len=0
    * Using Stream ID: 1 (easy handle 0x7f9198810600)
    > GET / HTTP/2
    > Host: foo.$DOMAIN
    > user-agent: curl/7.77.0
    > accept: */*
    > 
    < HTTP/2 200 
    < content-type: application/json
    < content-length: 377
    < access-control-allow-origin: *
    < server: Werkzeug/2.0.1 Python/3.8.11
    < date: Wed, 24 Nov 2021 11:44:25 GMT
    < via: 1.1 google
    < alt-svc: clear
    < 
    {
      "cloud_run_instance_id": 1667735529331472316,
      "cloud_run_service_account": "$PROJECT-ID.svc.id.goog",
      "cluster_name": "gke-1",
      "headers": {
        "Accept": "*/*",
        "Host": "foo1.endpoints.$PROJECT-ID.cloud.goog",
        "User-Agent": "curl/7.86.0",
        "Via": "1.1 google",
        "X-Cloud-Trace-Context": "f6a2f4ba46f09b910381569cb280f58e/5468962487031307443",
        "X-Forwarded-For": "104.199.75.203, 34.149.198.76",
        "X-Forwarded-Proto": "http"
      },
      "cluster_name": "gke-1", 
      "host_header": "foo.$DOMAIN", 
      "metadata": "foo", 
      "node_name": "gke-gke-1-default-pool-a72997f0-dmb7.us-central1-c.c.ravidalal-xyz-project-01.internal", 
      "pod_name": "foo-64fc448c5b-qvrbf", 
      "pod_name_emoji": "🧁", 
      "project_id": "ravidalal-xyz-project-01", 
      "timestamp": "2021-11-24T11:44:25", 
      "zone": "us-central1-c"
    }
    ```

### Cleanup

```bash
kubectl --context=gke-1 delete -f ingress.yaml
kubectl --context=gke-1 delete -f app.yaml
kubectl --context=gke-2 delete -f app.yaml
gcloud compute addresses delete mci-address --global --quiet
gcloud compute ssl-certificates delete mci-certs --quiet
```
