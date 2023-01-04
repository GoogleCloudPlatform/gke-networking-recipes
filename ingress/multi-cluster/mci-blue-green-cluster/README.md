# Multi-cluster Ingress Blue/Green Cluster Pattern

[Multi-cluster Ingress](https://cloud.google.com/kubernetes-engine/docs/concepts/ingress-for-anthos) for GKE is a cloud-hosted Ingress controller for GKE clusters. It's a Google-hosted service that supports deploying shared load balancing resources across clusters and across regions. 

> Note: in this guide, *MCI* will be used as shorthand for Multi-cluster Ingress.

### Use-case

The Blue/Green MCI cluster pattern is designed to address Kubernetes cluster lifecycle use cases where a given GCP region has two or more GKE clusters hosting the same application(s). 

Redundant GKE clusters are deployed so that one cluster can be removed from service at a time, upgraded, and returned to service, while the other cluster(s) continue to service client traffic. In this example, both clusters reside in the same GCP region to demonstrate a blue/green upgrade pattern where one cluster at a time can be removed from service, upgraded, and returned to service, all while clients can continue to access a given application.

This pattern could also be used cross-region, although that introduces concerns around data residency, so to keep things simple, this example demonstrates blue/green within a single region.

### Relevant documentation

- [Multi-cluster Ingress Concepts](https://cloud.google.com/kubernetes-engine/docs/concepts/ingress-for-anthos)
- [Setting Up Multi-cluster Ingress](https://cloud.google.com/kubernetes-engine/docs/how-to/ingress-for-anthos-setup)
- [Deploying Ingress Across Clusters](https://cloud.google.com/kubernetes-engine/docs/how-to/ingress-for-anthos)
- [Google Cloud External HTTP(S) Load Balancing](https://cloud.google.com/load-balancing/docs/https)

#### Versions

- GKE clusters on GCP
- All versions of GKE supported
- Tested and validated with 1.18.10-gke.1500 on Nov 14th 2020

### Networking Manifests

This recipe demonstrates deploying Multi-cluster Ingress across two clusters to expose a single service hosted across both clusters. Unlike the [prior example](../mci-basic) both clusters (`gke-1` and `gke-3`) reside in the same GCP region (`us-west1`), although they're placed in two different zones. Both clusters sit behind the same MultiClusterIngress and load balancer IP, and the load balancer will round-robin traffic between both clusters, as they sit within the same GCP region.

The two clusters in this example can be backends to MCI only if they are registered through Hub. Hub is a central registry of clusters that determines which clusters MCI can function across. A cluster must first be registered to Hub before it can be used with MCI.

There are two Custom Resources (CRs) that control multi-cluster load balancing - the MultiClusterIngress (MCI) and the MultiClusterService (MCS). The MCI below describes the desired traffic matching and routing behavior.

```yaml
apiVersion: networking.gke.io/v1
kind: MultiClusterIngress
metadata:
  name: foobar-ingress
  namespace: multi-cluster-demo
spec:
  template:
    spec:
      backend:
        serviceName: default-backend
        servicePort: 8080
      rules:
      - host: foo.example.com
        http:
          paths:
            - backend:
                serviceName: foo
                servicePort: 8080
```

Similar to the Kubernetes Service, the MultiClusterService (MCS) describes label selectors and other backend parameters to group pods in the desired way. Unlike the [prior example](../mci-basic), in this recipe we're just going to use a pair of MCSs, configured as the `default-backend` and `foo`, to exhibit failover behavior. Notice the `clusters` annotation in the MCS definitions below - we're explicitly specifying which clusters are hosting these services:

```yaml
apiVersion: networking.gke.io/v1
kind: MultiClusterService
metadata:
  name: foo
  namespace: multi-cluster-demo
  annotations:
    beta.cloud.google.com/backend-config: '{"ports": {"8080":"backend-health-check"}}'
spec:
  template:
    spec:
      selector:
        app: foo
      ports:
      - name: http
        protocol: TCP
        port: 8080
        targetPort: 8080
  clusters:
  - link: "us-west1-a/gke-1"
  - link: "us-west1-b/gke-3"
---
apiVersion: networking.gke.io/v1
kind: MultiClusterService
metadata:
  name: default-backend
  namespace: multi-cluster-demo
  annotations:
    beta.cloud.google.com/backend-config: '{"default": "backend-health-check"}'
spec:
  template:
    spec:
      selector:
        app: default-backend
      ports:
      - name: http
        protocol: TCP
        port: 8080
        targetPort: 8080
  clusters:
  - link: "us-west1-a/gke-1"
  - link: "us-west1-b/gke-3"
```

Now that you have the background knowledge and understanding of MCI, you can try it out yourself.

### Try it out

1. Download this repo and navigate to this folder

    ```bash
    $ git clone https://github.com/GoogleCloudPlatform/gke-networking-recipes.git
    Cloning into 'gke-networking-recipes'...

    $ cd gke-networking-recipes/multi-cluster-ingress/multi-cluster-blue-green-cluster
    ```

2. Deploy the two clusters `gke-1` and `gke-3` as specified in [cluster setup](../../../cluster-setup.md)

3. Now follow the steps for cluster registration with Hub and enablement of Multi-cluster Ingress.

    There are two manifests in this folder:

    - app.yaml is the manifest for the `default-backend` Deployment. This manifest should be deployed on both clusters.
    - ingress.yaml is the manifest for the MultiClusterIngress and MultiClusterService resources. These will be deployed only on the `gke-1` cluster as this was set as the config cluster and is the  cluster that the MCI controlller is listening to for updates.

4. Separately log in to each cluster and deploy the app.yaml manifest. You can configure these contexts as shown [here](../../../cluster-setup.md).

    ```bash
    $ kubectl --context=gke-1 apply -f app.yaml
    namespace/multi-cluster-demo created
    deployment.apps/default-backend created
    deployment.apps/foo created

    $ kubectl --context=gke-3 apply -f app.yaml
    namespace/multi-cluster-demo created
    deployment.apps/default-backend created
    deployment.apps/foo created

    # Shows that all pods are running and happy
    $ kubectl --context=gke-3 get deploy -n multi-cluster-demo
    NAME              READY   UP-TO-DATE   AVAILABLE   AGE
    default-backend   1/1     1            1           44m
    foo               2/2     2            2           44m
    ```


5. Now log into `gke-1` and deploy the ingress.yaml manifest.


    ```bash
    $ kubectl --context=gke-1 apply -f ingress.yaml
    multiclusteringress.networking.gke.io/foobar-ingress created
    multiclusterservice.networking.gke.io/foo created
    multiclusterservice.networking.gke.io/default-backend created
    backendconfig.cloud.google.com/backend-health-check created
    ```

6. It can take up to 10 minutes for the load balancer to deploy fully. Inspect the MCI resource to watch for events that indicate how the deployment is going. Then capture the IP address for the MCI ingress resource.

    ```bash
    $ kubectl --context=gke-1 describe mci/foobar-ingress -n multi-cluster-demo
    Name:         foobar-ingress
    Namespace:    multi-cluster-demo
    Labels:       <none>
    Annotations:  networking.gke.io/last-reconcile-time: Monday, 07-Dec-20 06:33:33 UTC
    API Version:  networking.gke.io/v1
    Kind:         MultiClusterIngress
    Metadata:
    Creation Timestamp:  2020-11-26T06:24:52Z
    Finalizers:
        mci.finalizer.networking.gke.io
    Generation:  6
    Managed Fields:
        API Version:  networking.gke.io/v1
        Fields Type:  FieldsV1
        fieldsV1:
        f:metadata:
            f:annotations:
            .:
            f:kubectl.kubernetes.io/last-applied-configuration:
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
        Time:         2020-12-06T04:38:51Z
        API Version:  networking.gke.io/v1beta1
        Fields Type:  FieldsV1
        fieldsV1:
        f:metadata:
            f:annotations:
            f:networking.gke.io/last-reconcile-time:
            f:finalizers:
        f:status:
            .:
            f:CloudResources:
            .:
            f:BackendServices:
            f:Firewalls:
            f:ForwardingRules:
            f:HealthChecks:
            f:NetworkEndpointGroups:
            f:TargetProxies:
            f:UrlMap:
            f:VIP:
        Manager:         Google-Multi-Cluster-Ingress
        Operation:       Update
        Time:            2020-12-07T06:33:33Z
    Resource Version:  6427773
    Self Link:         /apis/networking.gke.io/v1/namespaces/multi-cluster-demo/multiclusteringresses/foobar-ingress
    UID:               e50db551-53f3-4dd2-a7cd-ad43d3f922fd
    Spec:
    Template:
        Spec:
        Backend:
            Service Name:  default-backend
            Service Port:  8080
        Rules:
            Host:  foo.example.com
            Http:
            Paths:
                Backend:
                Service Name:  foo
                Service Port:  8080
    Status:
    Cloud Resources:
        Backend Services:
        mci-6rsucs-8080-multi-cluster-demo-default-backend
        mci-6rsucs-8080-multi-cluster-demo-foo
        Firewalls:
        mci-6rsucs-default-l7
        Forwarding Rules:
        mci-6rsucs-fw-multi-cluster-demo-foobar-ingress
        Health Checks:
        mci-6rsucs-8080-multi-cluster-demo-default-backend
        mci-6rsucs-8080-multi-cluster-demo-foo
        Network Endpoint Groups:
        zones/us-west1-a/networkEndpointGroups/k8s1-3efcccf3-multi-cluste-mci-default-backend-svc--80-b2c88574
        zones/us-west1-a/networkEndpointGroups/k8s1-3efcccf3-multi-cluster--mci-foo-svc-820zw3izx-808-91712bb3
        zones/us-west1-b/networkEndpointGroups/k8s1-6c1ae7d4-multi-cluste-mci-default-backend-svc--80-f8b91776
        zones/us-west1-b/networkEndpointGroups/k8s1-6c1ae7d4-multi-cluster--mci-foo-svc-820zw3izx-808-0787a440
        Target Proxies:
        mci-6rsucs-multi-cluster-demo-foobar-ingress
        URL Map:  mci-6rsucs-multi-cluster-demo-foobar-ingress
    VIP:        34.120.46.9
    Events:       <none>
    ```

    ```bash
    # capture the IP address for the MCI resource
    $ export MCI_ENDPOINT=$(kubectl --context=gke-1 get mci -n multi-cluster-demo -o yaml | grep "VIP" | awk 'END{ print $2}')
    ```

7. Now use the IP address from the MCI output to reach the load balancer. Running it several times should reflect that traffic is being load-balanced between `gke-1` and `gke-3`. We use `jq` to filter the output to make it easier to read but you could drop the `jq` portion of the command to see the full output.

    ```bash
    # Hitting the `foo` service attempt #1
    $ curl -s ${MCI_ENDPOINT} -H "host: foo.example.com" | jq -r '.zone, .cluster_name, .pod_name'
    us-west1-b
    gke-3
    foo-bf8dcc887-mbjtz

    # Hitting the `foo` service attempt #2
    $ curl -s ${MCI_ENDPOINT} -H "host: foo.example.com" | jq -r '.zone, .cluster_name, .pod_name'
    us-west1-a
    gke-1
    foo-bf8dcc887-fk27v
    ```


8. Now let's demonstrate how to take one of the clusters (in this case, `gke-1`) temporarily out of service. Start by sending requests to the MCI endpoint, accessing the `foo` service.

    ```bash
    $ while true; do curl -s ${MCI_ENDPOINT} -H "host: foo.example.com" | jq -c '{cluster: .cluster_name, pod: .pod_name}'; sleep 2; done

    {"cluster":"gke-1","pod":"foo-bf8dcc887-mf27w"}
    {"cluster":"gke-3","pod":"foo-bf8dcc887-hxt5w"}
    {"cluster":"gke-3","pod":"foo-bf8dcc887-hxt5w"}
    {"cluster":"gke-1","pod":"foo-bf8dcc887-mf27w"}
    {"cluster":"gke-3","pod":"foo-bf8dcc887-mbjtz"}
    {"cluster":"gke-1","pod":"foo-bf8dcc887-mf27w"}
    ...
    ```

    **Note:** This failover process will take several minutes to take effect.

9. Open up a second shell to remove `gke-1` from the `foo` MultiClusterService via `patch`. The patching process is going to remove `gke-1` from the `foo` MultiClusterService resource by only specifying `gke-3` in the `clusters` field:

    ```yaml
    metadata:
      name: foo
      namespace: multi-cluster-demo
    spec:
    clusters:
    - link: "us-west1-b/gke-3"
    ```

    ```bash
    $ kubectl --context=gke-1 patch MultiClusterService foo -n multi-cluster-demo --type merge --patch "$(cat ./patch.yaml)"
    multiclusterservice.networking.gke.io/foo patched

    $ kubectl --context=gke-1 describe MultiClusterService foo -n multi-cluster-demo
    Name:         foo
    Namespace:    multi-cluster-demo
    Labels:       <none>
    Annotations:  beta.cloud.google.com/backend-config: {"ports": {"8080":"backend-health-check"}}
    API Version:  networking.gke.io/v1
    Kind:         MultiClusterService
    Metadata:
    Creation Timestamp:  2020-12-06T04:38:52Z
    Finalizers:
        mcs.finalizer.networking.gke.io
    Generation:  4
    Managed Fields:
        API Version:  networking.gke.io/v1beta1
        Fields Type:  FieldsV1
        fieldsV1:
        f:metadata:
            f:finalizers:
            .:
            v:"mcs.finalizer.networking.gke.io":
        Manager:      Google-Multi-Cluster-Ingress
        Operation:    Update
        Time:         2020-12-06T04:38:52Z
        API Version:  networking.gke.io/v1
        Fields Type:  FieldsV1
        fieldsV1:
        f:metadata:
            f:annotations:
            .:
            f:beta.cloud.google.com/backend-config:
            f:kubectl.kubernetes.io/last-applied-configuration:
        f:spec:
            .:
            f:template:
            .:
            f:spec:
                .:
                f:ports:
                f:selector:
                .:
                f:app:
        Manager:      kubectl-client-side-apply
        Operation:    Update
        Time:         2020-12-07T06:32:31Z
        API Version:  networking.gke.io/v1
        Fields Type:  FieldsV1
        fieldsV1:
        f:spec:
            f:clusters:
        Manager:         kubectl-patch
        Operation:       Update
        Time:            2020-12-07T06:46:03Z
    Resource Version:  6432248
    Self Link:         /apis/networking.gke.io/v1/namespaces/multi-cluster-demo/multiclusterservices/foo
    UID:               6d39aa11-7cc4-4528-93d4-5808f34372e3
    Spec:
    Clusters:
        Link:  us-west1-b/gke-3
    Template:
        Spec:
        Ports:
            Name:         http
            Port:         8080
            Protocol:     TCP
            Target Port:  8080
        Selector:
            App:  foo
    Events:
    Type    Reason  Age                    From                              Message
    ----    ------  ----                   ----                              -------
    Normal  SYNC    7m18s (x448 over 26h)  multi-cluster-ingress-controller  Derived Service was ensured in cluster {us-west1-b/gke-3 gke-3}
    Normal  UPDATE  46s (x4 over 26h)      multi-cluster-ingress-controller  multi-cluster-demo/foo
    ```

10. Watch how all traffic eventually gets routed to `gke-3`. Because `gke-1` has been removed from the MCS, MCI will drain and remove all traffic to it.

    ```bash
    ...
    {"cluster":"gke-1","pod":"foo-bf8dcc887-fk27v"}
    {"cluster":"gke-1","pod":"foo-bf8dcc887-mf27w"}
    {"cluster":"gke-1","pod":"foo-bf8dcc887-fk27v"}
    {"cluster":"gke-1","pod":"foo-bf8dcc887-fk27v"}
    {"cluster":"gke-1","pod":"foo-bf8dcc887-mf27w"}
    {"cluster":"gke-1","pod":"foo-bf8dcc887-fk27v"}
    {"cluster":"gke-3","pod":"foo-bf8dcc887-hxt5w"}
    {"cluster":"gke-1","pod":"foo-bf8dcc887-fk27v"}
    {"cluster":"gke-3","pod":"foo-bf8dcc887-hxt5w"}
    {"cluster":"gke-3","pod":"foo-bf8dcc887-hxt5w"}
    {"cluster":"gke-1","pod":"foo-bf8dcc887-mf27w"}
    {"cluster":"gke-1","pod":"foo-bf8dcc887-mf27w"}
    {"cluster":"gke-1","pod":"foo-bf8dcc887-fk27v"} # <----- gke-1 cluster removed here
    {"cluster":"gke-3","pod":"foo-bf8dcc887-hxt5w"}
    {"cluster":"gke-3","pod":"foo-bf8dcc887-mbjtz"}
    {"cluster":"gke-3","pod":"foo-bf8dcc887-mbjtz"}
    {"cluster":"gke-3","pod":"foo-bf8dcc887-hxt5w"}
    {"cluster":"gke-3","pod":"foo-bf8dcc887-hxt5w"}
    {"cluster":"gke-3","pod":"foo-bf8dcc887-hxt5w"}
    {"cluster":"gke-3","pod":"foo-bf8dcc887-hxt5w"}
    {"cluster":"gke-3","pod":"foo-bf8dcc887-hxt5w"}
    {"cluster":"gke-3","pod":"foo-bf8dcc887-mbjtz"}
    {"cluster":"gke-3","pod":"foo-bf8dcc887-mbjtz"}
    ...
    ```

11. (Optional) Re-add `gke-1` by re-applying the original MCS definition.

    ```bash
    $ kubectl --context=gke-1 apply -f ingress.yaml
    multiclusteringress.networking.gke.io/foobar-ingress unchanged
    multiclusterservice.networking.gke.io/foo configured
    multiclusterservice.networking.gke.io/default-backend unchanged
    backendconfig.cloud.google.com/backend-health-check unchanged
    ```


### Cleanup

```bash

kubectl --context=gke-1 delete -f app.yaml
kubectl --context=gke-1 delete -f ingress.yaml
kubectl --context=gke-3 delete -f app.yaml
```