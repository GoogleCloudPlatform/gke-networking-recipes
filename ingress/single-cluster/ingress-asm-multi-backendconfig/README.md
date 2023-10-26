# Anthos Service Mesh Ingress with multiple backend configs

> **Note**
> This recipe deals with a rather complex subject. Therefore, unlike the other recipes, several steps are required to make everything work.

This recipe shows how to use a single ASM ingress gateway to run multiple different backends with different Backend Configs.
This can be used to e.g. protect some content behind the IAP (Like Montoring Tools or Admin GUI).

In order to use Backend Configs Istio Ingress Gateway needs to be exposed as a Layer7 (HTTP/HTTPS) Load Balancer, not as Layer 4 TCP Load balancer as it is by default.
This means other TCP based protocols can't be exposed via the same Ingress/External IP Address.
Replacing the default Kubernetes `LoadBalancer` service with an Ingress resource to get traffic to an Istio Ingress Gateway generally allows you to combine the features of Istio Ingress Gateways resource with the features of a [External HTTP(S) load balancer](https://cloud.google.com/load-balancing/docs/https) and [GKE ingress](https://cloud.google.com/kubernetes-engine/docs/how-to/ingress-features): besides Backend Configs, this also allows for example to use global load balancing or FrontendConfigs (such as for HTTP-to-HTTPS redirect).

In this example we will create 2 backend services: foo.example.com and bar.example.com.
While both services are served to the user via the Anthos Service Mesh ingress, we will protect bar.example.com with [Identity-Aware Proxy](https://cloud.google.com/iap)

> **Note**
> This tutorial assumes that you are familiar with the basic Istio concepts like Gateways and Virtual Services

## Steps

1. Go into the `ingress-asm-multi-backendconfig` directory: `cd ingress/single-cluster/ingress-asm-multi-backendconfig/`
2. Set some Variables we will need for the installation:
    ```bash
    export PROJECT_ID=<YOUR PROJECT ID>
    export LOCATION=us-west1-a
    export CLUSTER_NAME=gke-1
    gcloud config set project $PROJECT_ID
    ```
3. Setup the cluster:
    ASM requires [minimum 4vCPUs per node](https://cloud.google.com/service-mesh/docs/unified-install/anthos-service-mesh-prerequisites#cluster_requirements)
    and workload identity enabled please **don't** use the command from the default [setup guide](../../../cluster-setup.md)
    but use the following command to create your cluster:
    ```bash
    gcloud container clusters create $CLUSTER_NAME \
    --zone $LOCATION \
    --enable-ip-alias \
    --machine-type=e2-standard-4 \
    --workload-pool=${PROJECT_ID}.svc.id.goog \
    --release-channel rapid
    ```
4. After cluster creation receive the credentials for your cluster:
    ```bash
    gcloud container clusters get-credentials $CLUSTER_NAME \
    --zone $LOCATION
    ```
5. [Optional] if you are not using Cloud Shell [install ASM CLI](https://cloud.google.com/service-mesh/docs/unified-install/install-dependent-tools)
6. Install ASM into the cluster:
    ```bash
    asmcli install --project_id $PROJECT_ID \
    --cluster_location $LOCATION \
    --cluster_name $CLUSTER_NAME \
    --enable_all \
    --output_dir ./asm
    ```
    This also copies some examples into the previously not existing `asm` directory.
7. While waiting until `asmcli` installs ASM into your cluster use the time to [configure the IAP](https://cloud.google.com/iap/docs/enabling-kubernetes-howto#enabling_iap).
    Follow the steps in the guide until you have created the secret within the cluster.
8. As IAP requires HTTPS we need to create a self signed certificate that we can store in the Cluster and attach to the Ingress:
    ```bash
    openssl req -newkey rsa:2048 -nodes -keyout key.pem -x509 -days 365 -out certificate.pem \
    -subj "/CN=foo.example.com" \
    -addext "subjectAltName=DNS:foo.example.com,DNS:bar.example.com"
    kubectl create secret tls my-cert --key=key.pem --cert=certificate.pem
    ```
9. In order to tell ASM to watch the namespace and inject required configs we need to apply the label `istio-injection=enabled`
    Following this tutorial you will use the `default` namespace so please execute this command:
    ```bash
    kubectl label namespace default istio-injection=enabled --overwrite
    ```
10. After the installation and configuring the namespace injection install the istio-ingressgateway from the samples except for the [`service.yaml`](https://github.com/GoogleCloudPlatform/anthos-service-mesh-packages/blob/main/samples/gateways/istio-ingressgateway/service.yaml) which changed and will be deployed in the next step:
    ```bash
    kubectl apply -f asm/samples/gateways/istio-ingressgateway/serviceaccount.yaml
    kubectl apply -f asm/samples/gateways/istio-ingressgateway/role.yaml
    kubectl apply -f asm/samples/gateways/istio-ingressgateway/deployment.yaml
    ```
11. Deploy the modified ingress-gateway-service:
    ```bash
    kubectl apply -f istio-ingressgateway-service.yaml
    ```
    This step creates the following resources:
    * BackendConfigs:
        * `ingressgateway-default` configures the health check for the istio-ingressgateway.
        * `custom-backendconfig` configures the health check and enabled the Identity Aware Proxy.
    * Service `istio-ingressgateway`: In comparison to the default Service [shipped in the examples](https://github.com/GoogleCloudPlatform/anthos-service-mesh-packages/blob/main/samples/gateways/istio-ingressgateway/service.yaml) this service is of type `ClusterIP`.
        This in combination with the annotation `cloud.google.com/neg: '{"ingress": true}'` creates an HTTP/HTTPS Loadbalancer with [Container Native Load Balancing](https://cloud.google.com/kubernetes-engine/docs/how-to/container-native-load-balancing). \
        The Istio Ingress Gateway is exposed via 3 different Ports:
        * Port 15021 is used for the ingressgatweay health check and maps to the target port 15021.
        * In contrast to that, port 15022 (`http2`) and 15023 (`custom-backendconfig-port`) are both mapped to port 80 of the `istio-ingressgateway` which serves the normal user-facing traffic.

        While both ports (15022 und 15023) basically serve the same traffic now the annotation `cloud.google.com/backend-config: '{"ports": {"http2":""ingressgateway-default","custom-backendconfig-port":"custom-backendconfig"}}'` tells the GKE Ingress controller to apply the `ingressgateway-default`to port 15022(`http2`) and BackendConfig `custom-backendconfig` to port 15023(`custom-backendconfig-port`).
      > **Note**
      > The number of combinations of additional ports and BackendConfigs is arbitrarily extensible
    * Ingress `ingressgateway`: The Ingress has defined the `istio-ingressgateway` port 15022, which is associated with the BackendConfig `ingressgateway-default`, as the default.
        The more specific Host rule for `bar.example.com` is mapped to port 15023 of the `istio-ingressgateway`, which is associated with the BackendConfig `custom-backendconfig` and therefor requires IAP Authentication.
        This results in all traffic to `bar.example.com` is requiring IAP Authentication while all other traffic is not requiring IAP Authentication.
12. After some minutes you should be able to reach the ingress gateway via it's IP address:
    ```bash
    GCLB_IP=$(kubectl get ingress ingressgateway -o jsonpath="{.status.loadBalancer.ingress[0].ip}")
    echo "The Loadbalancer has IP ${GCLB_IP}"
    curl http://$GCLB_IP/ --head
    ```
    This will produce a HTTP 404 response as no backends are defined yet.
    But checking the Headers you can see that this is already coming from envoy (which powers the ingressgateway): `server: istio-envoy`
13. Deploy 2 services `foo` and `bar` with the corresponding Services and Virtual Services and the Istio Gateway:
    ```bash
    kubectl apply -f backend-services.yaml
    ```
14. After waiting another few minutes you are able to reach your backends:
    ```bash
    $ curl https://$GCLB_IP/ -k -H "Host: foo.example.com"
    {
        "cluster_name": "gke-1",
        "host_header": "foo.example.com",
        "metadata": "foo",
        "pod_name": "foo-6684f9c484-85jlk",
        "pod_name_emoji": "🧏🏾🏾‍♀",
        "project_id": "<PROJECT ID>",
        "timestamp": "2022-07-15T16:29:53",
        "zone": "us-west1-a"
    }
    $ curl https://$GCLB_IP/ -k -H "Host: bar.example.com" --head
    HTTP/2 302
    set-cookie: GCP_IAP_XSRF_NONCE_QiRHGwMKNrV-iunjVSj9mA=1; expires=Fri, 15-Jul-2022 16:40:21 GMT; path=/; Secure; HttpOnly
    location: https://accounts.google.com/o/oauth2/v2/auth?<REDACTED>
    x-goog-iap-generated-response: true
    content-length: 0
    date: Fri, 15 Jul 2022 16:30:21 GMT
    alt-svc: h3=":443"; ma=2592000,h3-29=":443"; ma=2592000
    ```
    > **Note**
    > These deployments use the `example.com` domain. In order to map them to your Ingress IP you have 3 options:
    > 1. Overwrite the host header. This makes the Load Balancer assume you are calling this DNS Name (this will be used in this example and is the easiest one to configure)
    > 2. Modify your local DNS resolution map example.com to yout GCLB IP
    > 3. Use a custom domain that you can point to your GCLB (Create a CNAME for *.domain.tld and replace example.com with your domain)
    >
    > **Only use option 2 or 3 if you know what you are doing!**

    While you will see a valid response from `foo.example.com` without the `--head` flag `bar.example.com` would just return an empty request.
    Note the Location header would redirect you to `https://accounts.google.com/o/oauth2/v2/auth` and the header shows `x-goog-iap-generated-response: true`.
    These are clear indications that the request is coming from IAP and not from the backend.
15. Unfortunately authenticating to the IAP using curl is a bit tricky.
    If you want to go the extra mile and get a valid response after authentication:
    In the Cloud Console go to `APIs and services` and then to `Credentials`. Click on the ClientID you created and add `http://localhost:4444` to the `Authorised redirect URIs`
    Now follow the documentation for [programmatic signing in to the application](https://cloud.google.com/iap/docs/authentication-howto#signing_in_to_the_application) to obtain your token.
    Use this token to authorize against the IAP.
    ```bash
    $ token=<YOUR TOKEN>
    $ curl https://$GCLB_IP/ -k -H "Host: bar.example.com"  -H "Authorization: Bearer ${token}"
    {
        "cluster_name": "gke-1",
        "host_header": "bar.example.com",
        "metadata": "bar",
        "pod_name": "bar-75cf6988f4-j8zdx",
        "pod_name_emoji": "🤽🏿🏿‍♂",
        "project_id": "<PROJECT ID>",
        "timestamp": "2022-07-15T16:31:25",
        "zone": "us-west1-a"
    }
    ```

### Testing
The test for this recipe will be skipped if the required environment variables are not set.
To run the test, you need to have a support email that follows the requirement described in [Programmatic OAuth clients](https://cloud.google.com/iap/docs/programmatic-oauth-clients). The test will be skipped if the environment variables are not set.
```
export SUPPORT_EMAIL=support-email
```
