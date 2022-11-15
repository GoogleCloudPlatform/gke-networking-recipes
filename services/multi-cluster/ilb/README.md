# Multi cluster service communication within same network

[Shared VPC](https://cloud.google.com/kubernetes-engine/docs/how-to/cluster-shared-vpc#managing_firewall_resources) Shared VPC enables multiple GKE clusters residing across different projects to be part of the same network. This enables different teams to manage their individual projects and communicate using the same shared VPC network centrally managed in the host project. Here we will look at how services residing across different clusters can communicate across cluster boundaries which are part of the same network.  

### Relevant documentation

- [Shared VPC Concepts](https://cloud.google.com/kubernetes-engine/docs/concepts/multi-cluster-services)
- [GCP Internal TCP load balancer](https://cloud.google.com/load-balancing/docs/internal)
- [Exposing kubernetes service via ILB](https://cloud.google.com/kubernetes-engine/docs/how-to/internal-load-balancing#create)

#### Versions

- GKE clusters on GCP
- 1.17 and later versions of GKE supported
- Tested and validated with v1.23.8-gke.1900 on Aug 23rd 2022

### Networking Manifests

This recipe demonstrates deploying a cluster (`gke-1`) and make it accessible to other cluster (`gke-2`) through Internal TCP/UDP Load Balancer. The Services in gke-1 are exposed via an Internal Load Balancer on a private IP address in the network. The pods in gke-2 will be able to communicate with gke-1 services via the internal ip address as they belong to the same network. 

![basic multi-cluster communication via ilb](../../../images/internal-lb-service.png)



### Try it out

1. Download this repo and navigate to this folder

    ```sh
    $ git clone https://github.com/GoogleCloudPlatform/gke-networking-recipes.git
    Cloning into 'gke-networking-recipes'...

    $ cd gke-networking-recipes/services/multi-cluster/ilb
    ```

2. Deploy the two clusters `gke-1` and `gke-2` as specified in [cluster setup](../../../cluster-setup.md)

3. There are two manifests in this folder:

    - app.yaml is the manifest for the `whereami` Deployment and Service.
    - ilb.yaml is the manifest for delpoying the whereami service with an Internal load balancer. NOTE: The ip address specified in ilb.yaml should be in the subnet CIDR range of the GKE cluster.

4. Now log into `gke-1` and deploy the app.yaml manifest. You can configure these contexts as shown [here](../../../cluster-setup.md).

    ```bash
    $ kubectl --context=gke-1 apply -f app.yaml
    namespace/multi-cluster-demo unchanged
    deployment.apps/whereami created
    service/whereami created

    # Shows that pod is running and happy
    $ kubectl --context=gke-1 get deploy -n multi-cluster-demo
    NAME              READY   UP-TO-DATE   AVAILABLE   AGE
    whereami          1/1     1            1           44m
    ```


5. Now create the service as an ilb with an internal ip address within the CIDR of the subnet of GKE cluster.

    ```bash
    $ kubectl --context=gke-1 apply -f ilb.yaml
    service/whereami-ilb created
    ```



6. Now try to access the internal load balancer endpoint from `gke-2`. Pod in gke-2 will be able to access the service in gke-1 via the Internal Load balancer ip address.

    ```bash
    $kubectl --context=gke-2 run -ti --rm --restart=Never --image=radial/busyboxplus:curl shell-$RANDOM -- curl <<ILB_IP_ADDRESS>> | jq -r '.zone, .cluster_name, .pod_name'
    us-west1-a
    gke-1
    whereami-559545767b-xrd4h
    ```

    ```

### Cleanup

```sh

kubectl --context=gke-1 delete -f app.yaml
kubectl --context=gke-2 delete -f app.yaml -f ilb.yaml
```
