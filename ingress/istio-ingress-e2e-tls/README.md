# Istio Ingress End to End TLS

[Istio Ingress Gateway](https://istio.io/v1.7/docs/tasks/traffic-management/ingress/ingress-control/ is typically used to expose applications inside an Istio Mesh to the outside world. Default installations deploys the Istio Ingress Gateway behind a Network Load Balancer (L4 LB) on GCP and have the Ingress gateway perform L7 capabilities like terminating TLS and path based routing. This recipe demonstrate how we can deploy an Istio Ingress Gateway behind a GCLB with Ingress, how to configure End to End Encryption From the User to the application pod and how to take advantage of some [GKE Ingress features](https://cloud.google.com/kubernetes-engine/docs/how-to/ingress-features#request_headers) to define policies and customize health check.

### Use-cases

- Deploying Istio with an Ingess Gateway and mTLS enabled 
- Exposing the Istio Ingress Gateway behind an HTTPS encrypted Load Balancer
- Configuring encryption between the Load Balancers and the Istio Ingress Gateway
- Granular control of HTTPS functionality through SSL Policies and HTTPS redirects 

### Relevant documentation

- [GKE Ingress Features](https://cloud.google.com/kubernetes-engine/docs/how-to/ingress-features)
- [GKE Ingress Concepts](https://cloud.google.com/kubernetes-engine/docs/concepts/ingress)
- [Ingress for External HTTP(S) Load Balancing](https://cloud.google.com/kubernetes-engine/docs/concepts/ingress-xlb)
- [HTTPS Redirects for GKE Ingress](https://cloud.google.com/kubernetes-engine/docs/how-to/ingress-features#https_redirect)
- [Google-managed SSL Certificates](https://cloud.google.com/kubernetes-engine/docs/how-to/managed-certs)
- [Secure Istio Gateway](https://istio.io/v1.7/docs/tasks/traffic-management/ingress/secure-ingress/)

#### Versions & Compatibility

- The [BackendConfig CRD](https://cloud.google.com/kubernetes-engine/docs/how-to/ingress-features#associating_backendconfig_with_your_ingress)  is only supported on GKE 1.16.15-gke.4091+.
- This recipes uses the latest release of [Istio 1.7](https://istio.io/v1.7/). It should also work with Istio 1.6.
- This Recipe have been tested and validated with [GKE 1.16.15-gke.4901](https://cloud.google.com/kubernetes-engine/docs/release-notes#november_12_2020_r37) and [Istio 1.7.5](https://istio.io/v1.7/) on Dec 2nd 2020

This recipe exposes one Service hosted on GKE to the internet through an Ingress resource. The Ingress leverages HTTPS to encrypt all traffic between the internet client and the Google Cloud load balancer. This recipe also leverages [Google-managed certificates](https://cloud.google.com/load-balancing/docs/ssl-certificates/google-managed-certs) to autogenerate the public certificate and attach it to the Ingress resource. This removes the need to self-generate and provide certificates for the load balancer. 

In addition to encrpting the client to GCLB traffic, we are also enabling Secure Istio Gateways with a self-signed certificate. Additional security policies are used to more granularly control the HTTPS behavior. [SSL policies](https://cloud.google.com/load-balancing/docs/ssl-policies-concepts) give the administrator the ability to define what kind of SSL and TLS negotiations that are permitted with this Ingress resource. Lastly we are enabling [mTLS](https://istio.io/v1.7/docs/reference/config/istio.mesh.v1alpha1/#MeshConfig) on Istio to ensure traffic between the Istio Ingress Gateway is encrypted and authenticated, effictivly acheiving End 2 End Encryption

![secure ingress](../../images/istio-ingress-e2e-tls.png)

### Networking Manifests

Several declarative Kubernetes resources are used in the deployment of this recipe. The primary one is the Ingress resource. It uses the following annotations to link to enable the security features mentioned above:

- `kubernetes.io/ingress.global-static-ip-name` deploys the Ingress with a static IP. This allows the IP address to remain the same even if the Ingress is redeployed in the future.
- `networking.gke.io/managed-certificates` references a managed certificate resource which generates a public certificate for the hostnames in the Ingress resource.
- `networking.gke.io/v1beta1.FrontendConfig` references a policy resource used to enable HTTPS redirects and an SSL policy.
- `kubernetes.io/ingress.allow-http` disables port 80 on the LoadBalancer VIP.

The Ingress resource also has single route rules for `foo.*.com` and `bar.*.com`. Note that Google-managed certificates requires that you have ownership over the certificate DNS domains. To complete this recipe will require that you replace `${DOMAIN}` with a domain you control.  This DNS domain must be mapped to the IP address used by the Ingress. This allows Google to do domain validation against it which is required for certificate provisioning. [Google domains](https://domains.google/) can be used to acquire domains that you can use for testing.

```yaml
apiVersion: networking.k8s.io/v1beta1
kind: Ingress
metadata:
  name: secure-ingress
  annotations:
    kubernetes.io/ingress.class: "gce"
    kubernetes.io/ingress.global-static-ip-name: gke-foobar-public-ip
    networking.gke.io/managed-certificates: foobar-certificate
    networking.gke.io/v1beta1.FrontendConfig: ingress-security-config
spec:
  rules:
  - host: foo.${DOMAIN}.com
    http:
      paths:
      - backend:
          serviceName: foo
          servicePort: 8080
  - host: bar.${DOMAIN}.com
    http:
      paths:
      - backend:
          serviceName: bar
          servicePort: 8080
```

The next resource is the  `FrontendConfig` which provides configuration for the [frontend of the Ingress.](https://cloud.google.com/kubernetes-engine/docs/how-to/ingress-features#associating_frontendconfig_with_your_ingress) This config enables HTTPS redirects. Note that it is enabled for the entire Ingress and so it will apply to all Services in the Ingress resource. The other field references an SSL policy. You'll create an SSL policy as a separate Google Cloud resource where you can specify which ciphers can be negotiated in the TLS connection.

```yaml
apiVersion: networking.gke.io/v1beta1
kind: FrontendConfig
metadata:
  name: ingress-security-config
spec:
  sslPolicy: gke-ingress-ssl-policy
  redirectToHttps:
    enabled: true
```

The managed certificate generation is goverened via the [ManagedCertificate resource.](https://cloud.google.com/kubernetes-engine/docs/how-to/managed-certs) The spec below will create a single SSL certificate resource with these two hostnames as SANs to the cert. 

```yaml
apiVersion: networking.gke.io/v1
kind: ManagedCertificate
metadata:
  name: foobar-certificate
spec:
  domains:
    - foo.${DOMAIN}.com
    - bar.${DOMAIN}.com
```

With these three resources, you are capable of securing your Ingress for production-ready traffic.

### Try it out

1. Download this repo and navigate to this folder

```sh
$ git clone https://github.com/GoogleCloudPlatform/gke-networking-recipes.git
Cloning into 'gke-networking-recipes'...

$ cd gke-networking-recipes/ingress/istio-ingress-e2e-tls
```

2. Deploy the cluster `gke-1` as specified in [cluster setup](../../cluster-setup.md)

3. Setup Istio

    * Download the Istio release.
      ```
      $ curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.7.5 sh -
      ```

    * [Prepare the GKE Cluster] (https://istio.io/v1.7/docs/setup/platform-setup/gke/) to install Istio.

    * Install istio using the Operator file
      ```
      $ istioctl install -f operator.yaml
      ```
    
    * Verify the Istio installation
      ```
      $ kubectl get pods -n istio-system
      ```
    
    * Your output will be different but both the **istio-ingressgateway** and **istiod** should be installed

    * Enable Automatic sidecar injection on the default namespace
      ```
      $ kubectl label namespace default istio-injection=enabled 
      ```

4. Create a static public IP address in your project.

```
$ gcloud compute addresses create --global gke-istio-ingress
```

5. Get the reserved public IP address and register it with your domain. The remaining of this recipes will assume that echoserver.${DOMAIN}.com resolves to the Public IP of the Ingress.\

```
gcloud compute addresses describe --global gke-istio-ingress 
```

6. Create an SSL policy. This policy specifies a broad set of modern ciphers and requires that cllients negotiate using TLS 1.2 or higher.

```
$ gcloud compute ssl-policies create gke-ingress-ssl-policy \
    --profile MODERN \
    --min-tls-version 1.2
```
7. Create the TLS root certificate, certificates and private keys for the Istio-Ingressgateway. This is the TLS certificates that will be used by the GCLB to encrypt traffic before sending it to the Ingress-gateway. Replace ${DOMAIN} with the appropriate value.

```
$ mkdir certs && cd certs

$ openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 -subj '/O=${DOMAIN}.com Inc./CN=.com' -keyout ${DOMAIN}.com.key -out ${DOMAIN}.com.crt

$ openssl req -out echoserver.${DOMAIN}.com.csr -newkey rsa:2048 -nodes -keyout echoserver.${DOMAIN}.com.key -subj "/CN=echoserver.${DOMAIN}.com/O=${DOMAIN} organization"

$ openssl x509 -req -days 365 -CA ${DOMAIN}.com.crt -CAkey ${DOMAIN}.com.key -set_serial 0 -in echoserver.${DOMAIN}.com.csr -out echoserver.${DOMAIN}.example.com.crt

cd ..

```

8. Add the certificate and key to the istio-system namespace

```
$ kubectl create -n istio-system secret tls echoserver-credentials --key=certs/echoserver.${DOMAIN}.com.key --cert=certs/echoserver.${DOMAIN}.com.crt
```

5. Now that all the Google Cloud resources have been created you can deploy your Kubernetes resources. Deploy the following manifest which deploys the whereami app and service, the FrontendConfig and BackendConfig Objects, the ManagedCertificate, and Ingress resource and Istio Objects (Gateway and VirtualService).

```
$ kubectl apply -f istio-ingress.yaml
managedcertificate.networking.gke.io/istio-ingress-cert created
frontendconfig.networking.gke.io/istio-ingress-fe-config created
backendconfig.cloud.google.com/istio-ingress-be-config created
ingress.networking.k8s.io/istio-ingress created
gateway.networking.istio.io/istio-ingressgateway created
virtualservice.networking.istio.io/echoserver created
service/whereami created
deployment.apps/whereami created
```

6. It will take up to 15 minutes for everything to be provisioned. You can determine the status by checking the Ingress resource events. When it is ready, the events should look like the following:


```bash
$ kubectl describe ingress secure-ingress
Name:             secure-ingress
Namespace:        default
Address:          xxx
Default backend:  default-http-backend:80 (10.8.2.7:8080)
Rules:
  Host            Path  Backends
  ----            ----  --------
  foo.gkeapp.com
                     foo:8080 (10.8.0.11:8080,10.8.1.9:8080)
  bar.gkeapp.com
                     bar:8080 (10.8.0.10:8080,10.8.0.9:8080)
Annotations:
  ingress.kubernetes.io/https-target-proxy:          k8s2-ts-j09o68xc-default-secure-ingress-jfepd28q
  ingress.kubernetes.io/target-proxy:                k8s2-tp-j09o68xc-default-secure-ingress-jfepd28q
  kubectl.kubernetes.io/last-applied-configuration:  {"apiVersion":"networking.k8s.io/v1beta1","kind":"Ingress","metadata":{"annotations":{"kubernetes.io/ingress.class":"gce","kubernetes.io/ingress.global-static-ip-name":"gke-foobar-public-ip","networking.gke.io/managed-certificates":"foobar-certificate"},"name":"secure-ingress","namespace":"default"},"spec":{"rules":[{"host":"foo.gkeapp.com","http":{"paths":[{"backend":{"serviceName":"foo","servicePort":8080}}]}},{"host":"bar.gkeapp.com","http":{"paths":[{"backend":{"serviceName":"bar","servicePort":8080}}]}}]}}

  kubernetes.io/ingress.class:                  gce
  kubernetes.io/ingress.global-static-ip-name:  gke-foobar-public-ip
  ingress.gcp.kubernetes.io/pre-shared-cert:    mcrt-49e7a559-5fe7-4f1d-abb1-8b047e8fd963
  ingress.kubernetes.io/forwarding-rule:        k8s2-fr-j09o68xc-default-secure-ingress-jfepd28q
  ingress.kubernetes.io/https-forwarding-rule:  k8s2-fs-j09o68xc-default-secure-ingress-jfepd28q
  networking.gke.io/managed-certificates:       foobar-certificate
  ingress.kubernetes.io/backends:               {"k8s-be-30401--0dfd9a8f1bfbe064":"HEALTHY","k8s1-0dfd9a8f-default-bar-8080-2c5d0692":"HEALTHY","k8s1-0dfd9a8f-default-foo-8080-4f0e99e4":"HEALTHY"}
  ingress.kubernetes.io/ssl-cert:               mcrt-49e7a559-5fe7-4f1d-abb1-8b047e8fd963
  ingress.kubernetes.io/url-map:                k8s2-um-j09o68xc-default-secure-ingress-jfepd28q
Events:
  Type    Reason  Age                   From                     Message
  ----    ------  ----                  ----                     -------
  Normal  Sync    118s (x115 over 17h)  loadbalancer-controller  Scheduled for sync

```

7. Now use your browser and connect to your URL (remember to use your own domain for this). You can validate the certificate by clicking on the lock icon in your browser. This will show that the foo.* and bar.* hostnames are both secured via the generated certificate.

![secure ingress certificate](../../images/secure-ingress-cert.png)

You can try to reach your application on HTTP but you won't be able to.

```bash
$ curl http://foo.gkeapp.com

<HTML><HEAD><meta http-equiv="content-type" content="text/html;charset=utf-8">
<TITLE>301 Moved</TITLE></HEAD><BODY>
<H1>301 Moved</H1>
The document has moved
<A HREF="https://foo.gkeapp.com/">here</A>.
</BODY></HTML>
```

You are now ready to serve securely on the internet!

### Cleanup

```sh
$ kubectl delete -f secure-ingress.yaml
$ gcloud compute addresses delete --global gke-foobar-public-ip
$ gcloud compute ssl-policies delete gke-ingress-ssl-policy
```