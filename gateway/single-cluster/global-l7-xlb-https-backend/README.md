# GKE Gateway in Single Cluster with HTTPS backend

TL;DR: This is basically just a small extension of [GKE Gateway in Single Cluster](../global-l7-xlb/) adding encryption between the HTTP(S) Load Balancer and the Deployment in your cluster using [HAProxy Sidecar](http://www.haproxy.org/) for terminating the HTTPS connection.

[GKE Gateway](https://cloud.google.com/kubernetes-engine/docs/concepts/gateway-api) is the GKE implementation of the Kubernetes Gateway API.
The Gateway API is an open source standard for service networking and is currently in the v1Alpha1 stage.
At this time it is recommended for testing and evaluation only.

This recipe does not provide a full walkthrough but instead just adds on the [GKE Gateway in Single Cluster](../global-l7-xlb/).
In order to understand what is done here please familiarize yourself with this recipe as this is required knowledge to understand the encryption.

## Use-cases

- Routing traffic to services deployed in multiple Kubernetes namespaces
- Encrypted traffic between the clients and HTTPS Load Balancer and between the HTTPS Load Balancer and the GKE Deployments

## Relevant documentation

- [GKE Gateway Concepts](https://cloud.google.com/kubernetes-engine/docs/concepts/gateway-api)
- [Deploying Gateway in Single cluster](https://cloud.google.com/kubernetes-engine/docs/how-to/deploying-gateways)
- [Kubernetes Gateway API Concepts](https://gateway-api.sigs.k8s.io/#gateway-api-concepts)
- [HTTPS (TLS) between load balancer and your application](https://cloud.google.com/kubernetes-engine/docs/concepts/ingress-xlb#https_tls_between_load_balancer_and_your_application)

## Versions

- GKE clusters on GCP
- GKE version 1.20 or later
- Tested and validated with v1.22.3-gke.700 on Jan 11th 2022

## How this works

### HAProxy sidecar

In order to make HTTPS possible HAProxy is run as a sidecar as the `whereami` application is not supporting HTTPS:

```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: foo
  namespace: gxlb-demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: foo
  template:
    metadata:
      labels:
        app: foo
        version: v1
    spec:
      containers:
      - name: whereami
        <WHEREAMI Specs>
      - name: haproxy
        image: haproxytech/haproxy-alpine:2.4
        ports:
          - name: https
            containerPort: 8443
        readinessProbe:
          httpGet:
            path: /
            port: 9000
            scheme: HTTP
        volumeMounts:
        - name: haproxy-volume
          mountPath: /usr/local/etc/haproxy
        - name: cert-volume
          mountPath: /usr/local/etc/haproxy-cert
      volumes:
      - name: haproxy-volume
        configMap:
          name: haproxy-config
      - name: cert-volume
        secret:
          secretName: haproxy-cert
```

Here instead of the previously exposed Port 8080 now port 8443 is exposed which is configured via the mounted ConfigMap to forward traffic to `127.0.0.1:8080`.
Additionally a self signed SSL Certificate is mounted and used in HA Proxy to encrypt the connection between the Load Balancer and the Deployment.

### Service and Health Check

As now also the health check for the backend of the Load Balancer is HTTPS a BackendConfig is required:

```yaml
apiVersion: cloud.google.com/v1
kind: BackendConfig
metadata:
  name: backend-health-check
  namespace: gxlb-demo
spec:
  healthCheck:
    requestPath: /healthz
    port: 8443
    type: HTTPS
```

The backend config now has to be matched to the Service via the `beta.cloud.google.com/backend-config` annotation and via the `spec.ports.appProtocol` field the protocol can be selected.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: foo
  namespace: gxlb-demo
  annotations:
    beta.cloud.google.com/backend-config: '{"default": "backend-health-check"}'
spec:
  selector:
    app: foo
  ports:
  - name: https-port
    port: 8443
    targetPort: 8443
    appProtocol: HTTPS
```

## Try it out

Now that the basics should be clear just try it out.
(Again most steps are just the same as in [GKE Gateway in Single Cluster](../global-l7-xlb/))

1. Download this repo and navigate to this folder

    ```bash
    git clone https://github.com/GoogleCloudPlatform/gke-networking-recipes.git
    Cloning into 'gke-networking-recipes'...

    cd gke-networking-recipes/gateway/single-cluster/global-l7-xlb-https-backend
    ```

1. Set up Environment variables

    ```bash
    export GKE_ZONE=GCP_CLOUD_ZONE # Pick a supported Zone for cluster
    ```

    NB: This tutorial uses Zonal Clusters, you can also use Regional Clusters. Replace a zone with a region and use the `--region` flag instead of `--zone` in the next steps.

1. Deploy the cluster as mentioned in [cluster setup](../../../cluster-setup.md#single-cluster-environment). Once done, come back to the next step.

1. Get the clusters credentials

    ```bash
    gcloud container clusters get-credentials gke-1 --zone=${GKE_ZONE}
    ```

1. Create a Static IP for the LoadBalancer and register it to DNS.

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

1. Provision Google-Managed Certificates

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

1. Install Gateway API CRDs

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

1. Check for the available GatewayClasses with the following command:

    ```bash
    kubectl get gatewayclass
    ```

    This output confirms that the GKE GatewayClasses are ready to use in your cluster:

    ```
    NAME          CONTROLLER
    gke-l7-rilb   networking.gke.io/gateway
    gke-l7-gxlb   networking.gke.io/gateway
    ```

1. Create self-signed certificate for backends using openssl.
    This certificate will never be exposed to the end user this is just used for encryption between the LB and your deployment.
    You don't need to worry about the correct Comon Name just put anything there. This is not validated by the Load Balancer.

    ```bash
    openssl req -newkey rsa:2048 -nodes -keyout key.pem -x509 -days 365 -out certificate.pem
    ```

    Provide required inputs when prompted by above command. Once key and certificate are generated successfully, create a a file that contains both certificate and the private key.

    ```bash
    cat certificate.pem key.pem >> mycert.pem
    rm certificate.pem key.pem
```

1. Create the namespace in the cluster (in order to place the certificate there already in advance)

  ```bash
  kubectl create namespace gxlb-demo-ns1
  kubectl create namespace gxlb-demo-ns2
  ```

1. Create the secrets for the self-signed certificate in each namespace

   ```bash
   kubectl create secret generic haproxy-cert --from-file=mycert.pem -n gxlb-demo-ns1
   kubectl create secret generic haproxy-cert --from-file=mycert.pem -n gxlb-demo-ns2
   ```

1. Edit the single-cluster-global-l7-xlb-recipe.yaml manifest to replace `$DOMAIN` with your domain.

  ```bash
  sed -i "s/\$DOMAIN/$DOMAIN/g" single-cluster-global-l7-xlb-https-backend.yaml
  ```

1. Deploy the `single-cluster-global-l7-xlb-https-backend.yaml`

  ```bash
  $ kubectl apply -f single-cluster-global-l7-xlb-https-backend.yaml
  configmap/haproxy-config created
  deployment.apps/foo created
  backendconfig.cloud.google.com/backend-health-check created
  service/foo created
  configmap/haproxy-config created
  deployment.apps/bar created
  backendconfig.cloud.google.com/backend-health-check created
  service/bar created
  gateway.networking.x-k8s.io/external-http created
  httproute.networking.x-k8s.io/foo created
  httproute.networking.x-k8s.io/bar created
  ```

1. It can take a few minutes for the load balancer to deploy fully. Validate the Gateway. Once the Gateway is created successfully, the *Addresses.Value* will show the static IP address.

    ```bash
    $ kubectl describe gateway external-http
    Name:         external-http
    Namespace:    default
    Labels:       <none>
    Annotations:  networking.gke.io/addresses:
                  networking.gke.io/backend-services:
                    gkegw-s4jy-gxlb-demo-ns1-foo-8443-z4gjz2ahpqen, gkegw-s4jy-gxlb-demo-ns2-bar-8443-graz3y1lvan6, gkegw-s4jy-kube-system-gw-serve404-80-7cq0...
                  networking.gke.io/firewalls: gkegw-l7--default
                  networking.gke.io/forwarding-rules: gkegw-s4jy-default-external-http-jy9mc97xb5yh
                  networking.gke.io/health-checks:
                    gkegw-s4jy-gxlb-demo-ns1-foo-8443-z4gjz2ahpqen, gkegw-s4jy-gxlb-demo-ns2-bar-8443-graz3y1lvan6, gkegw-s4jy-kube-system-gw-serve404-80-7cq0...
                  networking.gke.io/last-reconcile-time: Tuesday, 11-Jan-22 08:38:00 UTC
                  networking.gke.io/ssl-certificates:
                  networking.gke.io/target-proxies: gkegw-s4jy-default-external-http-jy9mc97xb5yh
                  networking.gke.io/url-maps: gkegw-s4jy-default-external-http-jy9mc97xb5yh
    API Version:  networking.x-k8s.io/v1alpha1
    Kind:         Gateway
    Metadata:
      Creation Timestamp:  2022-01-11T08:25:42Z
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
        Time:         2022-01-11T08:25:42Z
        API Version:  networking.x-k8s.io/v1alpha1
        Fields Type:  FieldsV1
        fieldsV1:
          f:status:
            f:addresses:
        Manager:      GoogleGKEGatewayController
        Operation:    Update
        Subresource:  status
        Time:         2022-01-11T08:25:53Z
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
        Manager:         GoogleGKEGatewayController
        Operation:       Update
        Time:            2022-01-11T08:26:23Z
      Resource Version:  16368
      UID:               e972a7f1-6ceb-4a4c-a0ac-14c711597cde
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
        Value:  34.149.136.123
      Conditions:
        Last Transition Time:  1970-01-01T00:00:00Z
        Message:               Waiting for controller
        Reason:                NotReconciled
        Status:                False
        Type:                  Scheduled
    Events:
      Type    Reason  Age                From                   Message
      ----    ------  ----               ----                   -------
      Normal  SYNC    13m (x2 over 13m)  sc-gateway-controller  default/external-http
      Normal  ADD     13m                sc-gateway-controller  default/external-http
      Normal  UPDATE  12m (x3 over 13m)  sc-gateway-controller  default/external-http
      Normal  SYNC    78s (x4 over 12m)  sc-gateway-controller  SYNC on default/external-http was a success
    ```

1. Validate the HTTP route. The output should look similar to this.

    ```bash
    $ kubectl describe httproute foo -n gxlb-demo-ns1
    Name:         foo
    Namespace:    gxlb-demo-ns1
    Labels:       <none>
    Annotations:  <none>
    API Version:  networking.x-k8s.io/v1alpha1
    Kind:         HTTPRoute
    Metadata:
      Creation Timestamp:  2022-01-11T08:25:42Z
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
        Time:         2022-01-11T08:25:42Z
        API Version:  networking.x-k8s.io/v1alpha1
        Fields Type:  FieldsV1
        fieldsV1:
          f:status:
            .:
            f:gateways:
        Manager:         GoogleGKEGatewayController
        Operation:       Update
        Subresource:     status
        Time:            2022-01-11T08:26:23Z
      Resource Version:  18021
      UID:               783b0d34-7cc9-4a9e-b604-7655a781359a
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
          Port:          8443
          Service Name:  foo
          Weight:        1
        Matches:
          Path:
            Type:   Prefix
            Value:  /
    Status:
      Gateways:
        Conditions:
          Last Transition Time:  2022-01-11T08:42:03Z
          Message:
          Reason:                RouteAdmitted
          Status:                True
          Type:                  Admitted
          Last Transition Time:  2022-01-11T08:42:03Z
          Message:
          Reason:                ReconciliationSucceeded
          Status:                True
          Type:                  Reconciled
        Gateway Ref:
          Name:       external-http
          Namespace:  default
    Events:
      Type    Reason  Age                From                   Message
      ----    ------  ----               ----                   -------
      Normal  ADD     17m                sc-gateway-controller  gxlb-demo-ns1/foo
      Normal  SYNC    72s (x5 over 16m)  sc-gateway-controller  Bind of HTTPRoute "gxlb-demo-ns1/foo" to Gateway "default/external-http" was a success
      Normal  SYNC    72s (x5 over 16m)  sc-gateway-controller  Reconciliation of HTTPRoute "gxlb-demo-ns1/foo" bound to Gateway "default/external-http" was a success
    ```

1. Now use the hostnames from the HTTPRoute resources to reach the load balancer.
   Make sure to have the DNS for `foo.$DOMAIN` and `bar.$DOMAIN` set to the IP address of your Load Balancer.

    ```bash
    $ curl https://foo.$DOMAIN
    {
      "cluster_name": "gke-1",
      "host_header": "foo.$DOMAIN",
      "metadata": "foo",
      "node_name": "gke-gke-1-default-pool-d67e4eab-g0lq.europe-west4-b.c.$PROJECT_ID.internal",
      "pod_name": "foo-77558b665d-4kwpc",
      "pod_name_emoji": "🧏🏼‍♂️",
      "project_id": "$PROJECT_ID",
      "timestamp": "2022-01-11T09:02:18",
      "zone": "europe-west4-b"
    }
    ```

    and

    ```bash
    $ curl https://bar.$DOMAIN
    {
      "cluster_name": "gke-1",
      "host_header": "bar.$DOMAIN",
      "metadata": "bar",
      "node_name": "gke-gke-1-default-pool-d67e4eab-z3g7.europe-west4-b.c.$PROJECT_ID.internal",
      "pod_name": "bar-88589f454-zfz9k",
      "pod_name_emoji": "🔺",
      "project_id": "$PROJECT_ID",
      "timestamp": "2022-01-11T09:07:59",
      "zone": "europe-west4-b"
    }
    ```

    *Note* If you get some message like `curl: (35) OpenSSL SSL_connect: SSL_ERROR_SYSCALL in connection to foo.$DOMAIN:443` it might take a few more minutes until your SSL certificate is ready and propagated.
    You can check that via

    ```bash
    $ gcloud compute ssl-certificates describe gxlb-cert
    certificate: |
      <CERTIFICATE>
    creationTimestamp: '2022-01-10T23:59:36.399-08:00'
    expireTime: '2022-04-11T00:34:55.000-07:00'
    id: '<CERT IT>'
    kind: compute#sslCertificate
    managed:
      domainStatus:
        bar.$DOMAIN: ACTIVE22
        foo.$DOMAIN: ACTIVE
      domains:
      - foo.$DOMAIN
      - bar.$DOMAIN
      status: ACTIVE
    name: gxlb-cert
    selfLink: https://www.googleapis.com/compute/v1/projects/$PROJECT_ID/global/sslCertificates/gxlb-cert
    subjectAlternativeNames:
    - foo.$DOMAIN
    - bar.$DOMAIN
    type: MANAGED
    ```

    Ass soon as you see the certificate part and your domains are `ACTIVE` it will only take a short time until you app is accessible.
    If you don't see your certificate becoming ready make sure that your DNS entries for `foo.$DOMAIN` and `bar.$DOMAIN` are set to the Load Balancer IP address.

### Cleanup

Delete only the resources in the cluster:

```bash
kubectl delete -f single-cluster-global-l7-xlb-https-backend.yaml
```

Delete the whole cluster:

```bash
gcloud container clusters delete gke-1 --zone=${GKE_ZONE}
```

Delete other GCP resources (required for both options above):

```bash
gcloud compute addresses delete gke-gxlb-ip --global --quiet
gcloud compute ssl-certificates delete gxlb-cert --quiet
```
