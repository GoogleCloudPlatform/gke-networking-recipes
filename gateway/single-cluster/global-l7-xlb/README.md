# GKE Gateway in Single Cluster

[GKE Gateway](https://cloud.google.com/kubernetes-engine/docs/concepts/gateway-api) is the GKE implementation of the Kubernetes Gateway API. The Gateway API is an open source standard for service networking and is currently in the v1Alpha1 stage. At this time it is recommended for testing and evaluation only.

This recipe provides a walkthrough of GKE Gateway using **gke-l7-gxlb** (Global external HTTP(S) load balancers built on External HTTP(S) Load Balancing) GKE [GatewayClass](https://cloud.google.com/kubernetes-engine/docs/concepts/gateway-api#gatewayclass).


## Use-cases

- Routing traffic to services deployed in multiple Kubernetes namespaces
- Encrypted traffic between the clients and HTTPS Load Balancer

## Relevant documentation

- [GKE Gateway Concepts](https://cloud.google.com/kubernetes-engine/docs/concepts/gateway-api)
- [Deploying Gateway in Single cluster](https://cloud.google.com/kubernetes-engine/docs/how-to/deploying-gateways)
- [Kubernetes Gateway API Concepts](https://gateway-api.sigs.k8s.io/#gateway-api-concepts)

## Versions

- GKE clusters on GCP
- GKE version 1.20 or later
- Tested and validated with 1.21.5-gke.1302 on Dec 4th 2021

### Networking Manifests

This recipe demonstrates deploying [Gateway](https://cloud.google.com/kubernetes-engine/docs/concepts/gateway-api#gateway) and [HTTPRoute](https://cloud.google.com/kubernetes-engine/docs/concepts/gateway-api#httproute) in a single GKE cluster. One Gateway resource to expose two different services hosted in two different namespaces.

The cluster `gke-1` is a regional cluster. The Gateway is hosted in default namespace. Two services in two different namespaces (other than default namespace). The Gateway (GKE load balancer) will match the traffic and send it to the right service depending on the request.

This Recipe also demonstrates how to enable HTTPS on Gateway Load Balancer using Google-managed certificate.

This example is using two applications; foo and bar. The *foo* applicaion is deployed in `NAMESPACE#1` and *bar* application is deployed in `NAMESPACE#2`. The External HTTPS Load Balancer is designed to route traffic to the services based on the request host name header. 

The Gateway below also uses:

- A [Google-Managed Certificate](https://cloud.google.com/kubernetes-engine/docs/how-to/deploying-gateways#tls_between_client_and_gateway)
- A public [Static IP](https://cloud.google.com/compute/docs/ip-addresses/reserve-static-external-ip-address) used as Gateway address

```yaml
kind: Gateway
apiVersion: networking.x-k8s.io/v1alpha1
metadata:
  name: external-http
spec:
  gatewayClassName: gke-l7-gxlb
  listeners:
  - protocol: HTTPS
    port: 443
    routes:
      kind: HTTPRoute
      namespaces:
        from: "All"
    tls:
      mode: Terminate
      options:
        networking.gke.io/pre-shared-certs: gxlb-cert
  addresses:
  - type: NamedAddress
    value: gke-gxlb-ip
```

The *spec.listeners.routes* in Gateway defines which routes can bind to the Gateway. In this example, routes from all namespaces are allowed. We can also use `selector` to restrict the routes binding to specific namespaces or services.

The HTTPRoute resource defines how HTTP and HTTPS requests received by a Gateway are directed to Services. Application developers create HTTPRoutes to expose their applications through Gateways.


```yaml
kind: HTTPRoute
apiVersion: networking.x-k8s.io/v1alpha1
metadata:
  name: foo
  namespace: gxlb-demo-ns1
spec:
  gateways:
    allow: FromList
    gatewayRefs:
    - name: external-http
      namespace: default
  hostnames:
  - "foo.$DOMAIN"
  rules:
  - forwardTo:
    - serviceName: foo
      port: 8080
```

The HTTPRoutes resources for two services (foo and bar) define which Gateway it can route traffic from (external-http in default namespace), which Services to route to (foo/bar), and rules that define what traffic the HTTPRoute matches (request host name is foo/bar.$DOMAIN). 

Now that you have the background knowledge and understanding of GKE Gateway, you can try it out yourself.

## Try it out

1. Download this repo and navigate to this folder

    ```bash
    git clone https://github.com/GoogleCloudPlatform/gke-networking-recipes.git
    Cloning into 'gke-networking-recipes'...

    cd gke-networking-recipes/gateway/single-cluster/global-l7-xlb
    ```

2. Set up Environment variables

    ```bash
    export PROJECT_ID=$(gcloud config get-value project) # or your preferred project
    export GKE_REGION=GCP_CLOUD_REGION # Pick a supported Zone for cluster
    ```

    NB: This tutorial uses Regional Clusters, you can also use Zonal Clusters. Replace a region with a zone and use the ```--zone``` flag instead of ```--region``` in the next steps.

3. Deploy the cluster as mentioned in [cluster setup](../../../cluster-setup.md#single-cluster-environment). Once done, come back to the next step.

4. Get the clusters credentials

    ```bash
    gcloud container clusters get-credentials gke-1 --region=us-central1
    ```

5. Create a Static IP for the LoadBalancer and register it to DNS.

    In order to use Google-Managed Certificated, a static IP needs to be reserved and registered with your DNS Server.

    Start by creating a public Static IP.

    ```bash
    gcloud compute addresses create gke-gxlb-ip --global
    ```

    Get the reserved IP.

    ```bash
    gcloud compute addresses list
    ```

    Copy the IP address (not the name the actual IP in the form x.x.x.x). You will need to register it as an A record with your DNS Server for every host you intend to configure the LoadBalancer for. In this example you will need the IP address to be mapped to ```bar.$DOMAIN``` and ```foo.$DOMAIN```. Replace ```$DOMAIN``` with your own domain, Exp: ```mycompany.com```.

6. Provision Google-Managed Certificates

    Export you domain suffix as an environment variable

    ```bash
    export DOMAIN=mycompany.com
    ```

    We will use Google-Managed Certificates in this example to provision and HTTPS LoadBalancer, run the following command.

    ```bash
    gcloud compute ssl-certificates create gxlb-cert --domains=foo.${DOMAIN},bar.${DOMAIN} --global
    ```

    Check that the certificates have been created

    ```bash
    gcloud compute ssl-certificates list
    ```

    The MANAGED_STATUS will indicate ```PROVISIONNING```. This is normal, the certificates will be provisioned when you deploy the Gateway.

7. Install Gateway API CRDs
   
    ```bash
    kubectl kustomize "github.com/kubernetes-sigs/gateway-api/config/crd?ref=v0.3.0" | kubectl apply -f -
    ```

    The following CRDs are installed:

    ```
    customresourcedefinition.apiextensions.k8s.io/backendpolicies.networking.x-k8s.io created
    customresourcedefinition.apiextensions.k8s.io/gatewayclasses.networking.x-k8s.io created
    customresourcedefinition.apiextensions.k8s.io/gateways.networking.x-k8s.io created
    customresourcedefinition.apiextensions.k8s.io/httproutes.networking.x-k8s.io created
    customresourcedefinition.apiextensions.k8s.io/tcproutes.networking.x-k8s.io created
    customresourcedefinition.apiextensions.k8s.io/tlsroutes.networking.x-k8s.io created
    customresourcedefinition.apiextensions.k8s.io/udproutes.networking.x-k8s.io created
    ```

8. Check for the available GatewayClasses with the following command:

    ```bash
    kubectl get gatewayclass
    ```

    This output confirms that the GKE GatewayClasses are ready to use in your cluster:

    ```
    NAME          CONTROLLER
    gke-l7-rilb   networking.gke.io/gateway
    gke-l7-gxlb   networking.gke.io/gateway
    ```

9.  Edit the single-cluster-global-l7-xlb-recipe.yaml manifest to replace `$DOMAIN` with your domain.
 
10. Log in to the cluster and deploy the single-cluster-global-l7-xlb-recipe.yaml manifest.

    ```bash
    kubectl apply -f single-cluster-global-l7-xlb-recipe.yaml
    namespace/gxlb-demo-ns1 created
    namespace/gxlb-demo-ns2 created
    deployment.apps/foo created
    service/foo created
    deployment.apps/bar created
    service/bar created
    gateway.networking.x-k8s.io/external-http created
    httproute.networking.x-k8s.io/foo created
    httproute.networking.x-k8s.io/bar created
    ```

11. It can take a few minutes for the load balancer to deploy fully. Validate the Gateway. Once the Gateway is created successfully, the *Addresses.Value* will show the static IP address. 

    ```bash
    kubectl describe gateway external-http

    Name:         external-http
    Namespace:    default
    Labels:       <none>
    Annotations:  networking.gke.io/addresses: 
                  networking.gke.io/backend-services: gkegw-pqb5-kube-system-gw-serve404-80-7cq0brelgzex
                  networking.gke.io/firewalls: gkegw-l7--vpc-1
                  networking.gke.io/forwarding-rules: gkegw-pqb5-default-external-http-jy9mc97xb5yh
                  networking.gke.io/health-checks: gkegw-pqb5-kube-system-gw-serve404-80-7cq0brelgzex
                  networking.gke.io/last-reconcile-time: Saturday, 04-Dec-21 12:56:21 UTC
                  networking.gke.io/ssl-certificates: 
                  networking.gke.io/target-proxies: gkegw-pqb5-default-external-http-jy9mc97xb5yh
                  networking.gke.io/url-maps: gkegw-pqb5-default-external-http-jy9mc97xb5yh
    API Version:  networking.x-k8s.io/v1alpha1
    Kind:         Gateway
    Metadata:
      Creation Timestamp:  2021-12-04T12:55:38Z
      Finalizers:
        gateway.finalizer.networking.gke.io
      Generation:  1
      Managed Fields:
        API Version:  networking.x-k8s.io/v1alpha1
        Fields Type:  FieldsV1
        fieldsV1:
          f:metadata:
            f:annotations:
              .:
              f:kubectl.kubernetes.io/last-applied-configuration:
          f:spec:
            .:
            f:addresses:
            f:gatewayClassName:
            f:listeners:
        Manager:      kubectl-client-side-apply
        Operation:    Update
        Time:         2021-12-04T12:55:38Z
        API Version:  networking.x-k8s.io/v1alpha1
        Fields Type:  FieldsV1
        fieldsV1:
          f:metadata:
            f:annotations:
              f:networking.gke.io/addresses:
              f:networking.gke.io/backend-services:
              f:networking.gke.io/firewalls:
              f:networking.gke.io/forwarding-rules:
              f:networking.gke.io/health-checks:
              f:networking.gke.io/last-reconcile-time:
              f:networking.gke.io/ssl-certificates:
              f:networking.gke.io/target-proxies:
              f:networking.gke.io/url-maps:
            f:finalizers:
              .:
              v:"gateway.finalizer.networking.gke.io":
          f:status:
            f:addresses:
        Manager:         GoogleGKEGatewayController
        Operation:       Update
        Time:            2021-12-04T12:56:21Z
      Resource Version:  149805
      UID:               c445b6bc-e672-4f3b-b633-44f17c763bab
    Spec:
      Addresses:
        Type:              NamedAddress
        Value:             gke-gxlb-ip
      Gateway Class Name:  gke-l7-gxlb
      Listeners:
        Port:      443
        Protocol:  HTTPS
        Routes:
          Group:  networking.x-k8s.io
          Kind:   HTTPRoute
          Namespaces:
            From:  All
        Tls:
          Mode:  Terminate
          Options:
            networking.gke.io/pre-shared-certs:  gxlb-cert
          Route Override:
            Certificate:  Deny
    Status:
      Addresses:
        Type:   IPAddress
        Value:  x.x.x.x
      Conditions:
        Last Transition Time:  1970-01-01T00:00:00Z
        Message:               Waiting for controller
        Reason:                NotReconciled
        Status:                False
        Type:                  Scheduled
    Events:
      Type    Reason  Age                From                   Message
      ----    ------  ----               ----                   -------
      Normal  ADD     86s                sc-gateway-controller  default/external-http
      Normal  UPDATE  43s (x3 over 86s)  sc-gateway-controller  default/external-http
      Normal  SYNC    43s                sc-gateway-controller  SYNC on default/external-http was a success
        
    ```

12. Validate the HTTP route. The output should look similar to this.
    
    ```bash
    kubectl describe httproute foo -n gxlb-demo-ns1

    Name:         foo
    Namespace:    gxlb-demo-ns1
    Labels:       <none>
    Annotations:  <none>
    API Version:  networking.x-k8s.io/v1alpha1
    Kind:         HTTPRoute
    Metadata:
      Creation Timestamp:  2021-12-04T13:02:30Z
      Generation:          1
      Managed Fields:
        API Version:  networking.x-k8s.io/v1alpha1
        Fields Type:  FieldsV1
        fieldsV1:
          f:metadata:
            f:annotations:
              .:
              f:kubectl.kubernetes.io/last-applied-configuration:
          f:spec:
            .:
            f:gateways:
              .:
              f:allow:
              f:gatewayRefs:
            f:hostnames:
            f:rules:
        Manager:      kubectl-client-side-apply
        Operation:    Update
        Time:         2021-12-04T13:02:30Z
        API Version:  networking.x-k8s.io/v1alpha1
        Fields Type:  FieldsV1
        fieldsV1:
          f:status:
            .:
            f:gateways:
        Manager:         GoogleGKEGatewayController
        Operation:       Update
        Time:            2021-12-04T13:03:40Z
      Resource Version:  153160
      UID:               735eec5f-f7ac-4da7-8694-9f4574c9adbd
    Spec:
      Gateways:
        Allow:  FromList
        Gateway Refs:
          Name:       external-http
          Namespace:  default
      Hostnames:
        foo.$DOMAIN
      Rules:
        Forward To:
          Port:          8080
          Service Name:  foo
          Weight:        1
        Matches:
          Path:
            Type:   Prefix
            Value:  /
    Status:
      Gateways:
        Conditions:
          Last Transition Time:  2021-12-04T13:03:40Z
          Message:               
          Reason:                RouteAdmitted
          Status:                True
          Type:                  Admitted
          Last Transition Time:  2021-12-04T13:03:40Z
          Message:               
          Reason:                ReconciliationSucceeded
          Status:                True
          Type:                  Reconciled
        Gateway Ref:
          Name:       external-http
          Namespace:  default
    Events:
      Type    Reason  Age   From                   Message
      ----    ------  ----  ----                   -------
      Normal  ADD     92s   sc-gateway-controller  gxlb-demo-ns1/foo
      Normal  SYNC    22s   sc-gateway-controller  Bind of HTTPRoute "gxlb-demo-ns1/foo" to Gateway "default/external-http" was a success
      Normal  SYNC    22s   sc-gateway-controller  Reconciliation of HTTPRoute "gxlb-demo-ns1/foo" bound to Gateway "default/external-http" was a success
    ```

13. Now use the hostnames from the HTTPRoute resources to reach the load balancer.

    ```bash
    curl -v -L https://foo.$DOMAIN

    *   Trying x.x.x.x:443...
    * Connected to foo.$DOMAIN (x.x.x.x) port 443 (#0)
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
    * Using Stream ID: 1 (easy handle 0x7ff2e0010c00)
    > GET / HTTP/2
    > Host: foo.$DOMAIN
    > user-agent: curl/7.77.0
    > accept: */*
    > 
    < HTTP/2 200 
    < content-type: application/json
    < content-length: 381
    < access-control-allow-origin: *
    < server: Werkzeug/2.0.1 Python/3.8.11
    < date: Sat, 04 Dec 2021 13:17:17 GMT
    < via: 1.1 google
    < alt-svc: clear
    < 
    {
      "cluster_name": "gke-1", 
      "host_header": "foo.$DOMAIN", 
      "metadata": "foo", 
      "node_name": "gke-gke-1-default-pool-b40742e5-9608.us-central1-c.c.$PROJECT_ID.internal", 
      "pod_name": "foo-5db8bcc6ff-htssf", 
      "pod_name_emoji": "💏🏾", 
      "project_id": "$PROJECT_ID", 
      "timestamp": "2021-12-04T13:17:17", 
      "zone": "us-central1-c"
    }
    ```

    ```bash
    curl -v -L https://bar.$DOMAIN

    *   Trying x.x.x.x:443...
    * Connected to bar.$DOMAIN (x.x.x.x) port 443 (#0)
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
    *  subjectAltName: host "bar.$DOMAIN" matched cert's "bar.$DOMAIN"
    *  issuer: C=US; O=Google Trust Services LLC; CN=GTS CA 1D4
    *  SSL certificate verify ok.
    * Using HTTP2, server supports multi-use
    * Connection state changed (HTTP/2 confirmed)
    * Copying HTTP/2 data in stream buffer to connection buffer after upgrade: len=0
    * Using Stream ID: 1 (easy handle 0x7fe99a810600)
    > GET / HTTP/2
    > Host: bar.$DOMAIN
    > user-agent: curl/7.77.0
    > accept: */*
    > 
    < HTTP/2 200 
    < content-type: application/json
    < content-length: 376
    < access-control-allow-origin: *
    < server: Werkzeug/2.0.1 Python/3.8.11
    < date: Sat, 04 Dec 2021 13:19:36 GMT
    < via: 1.1 google
    < alt-svc: clear
    < 
    {
      "cluster_name": "gke-1", 
      "host_header": "bar.$DOMAIN", 
      "metadata": "bar", 
      "node_name": "gke-gke-1-default-pool-ba0c218e-cwq1.us-central1-a.c.$PROJECT_ID.internal", 
      "pod_name": "bar-f8cd8cbd5-kngk5", 
      "pod_name_emoji": "👏", 
      "project_id": "$PROJECT_ID", 
      "timestamp": "2021-12-04T13:19:36", 
      "zone": "us-central1-a"
    }
    ```

The successful response from both URLs confirm that the Gateway is routing the traffic as configured.

### Cleanup

  ```bash
  kubectl delete -f single-cluster-global-l7-xlb-recipe.yaml
  gcloud compute addresses delete gke-gxlb-ip --global --quiet
  gcloud compute ssl-certificates delete gxlb-cert --quiet
  ```
