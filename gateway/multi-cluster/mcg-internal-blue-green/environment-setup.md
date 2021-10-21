## Set up environment variable

This will be referenced in upcoming command line examples.

```bash
$ export PROJECT=$(gcloud config get-value project) # or your preferred project
```

## Multi-cluster environment deployment


1. Enable the required APIs and features for your GCP project as described [here](https://cloud.google.com/kubernetes-engine/docs/how-to/multi-cluster-ingress-setup#before_you_begin)

    > Link needs to be updated to reference Gateway controller documentation

    ```bash
    $ gcloud services enable \
    container.googleapis.com \
    gkeconnect.googleapis.com \
    gkehub.googleapis.com \
    trafficdirector.googleapis.com \
    cloudresourcemanager.googleapis.com \
    multiclusterservicediscovery.googleapis.com \
    multiclusteringress.googleapis.com

    $ gcloud alpha container hub multi-cluster-services enable

    $ gcloud projects add-iam-policy-binding $PROJECT \
    --member "serviceAccount:$PROJECT.svc.id.goog[gke-mcs/gke-mcs-importer]" \
    --role "roles/compute.networkViewer"
    ```
  
    

2. Deploy two GKE clusters within your Google Cloud project with [Workload Identity](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity) enabled

    ```bash
    $ gcloud container clusters create gke-blue \
    --zone us-west1-a \
    --enable-ip-alias \
    --release-channel rapid \
    --workload-pool=${PROJECT}.svc.id.goog \

    $ gcloud container clusters create gke-green \
    --zone us-west1-b \
    --enable-ip-alias \
    --release-channel rapid \
    --workload-pool=${PROJECT}.svc.id.goog \
    ```

3. Rename contexts

    The prior step will have added credentials for your new clusters to your `kubeconfig`, but let's rename the contexts to something a little shorter:

    ```bash
    $ kubectl config rename-context gke_${PROJECT}_us-west1-a_gke-blue gke-blue

    $ kubectl config rename-context gke_${PROJECT}_us-west1-b_gke-green gke-green
    ```

4. [Register](https://cloud.google.com/anthos/multicluster-management/connect/registering-a-cluster) your two clusters (`gke-blue` and `gke-green`) using [Workload Identity](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity). 

    There are a few steps to complete as part of the registration process from the [link](https://cloud.google.com/anthos/multicluster-management/connect/registering-a-cluster) above. A quick hint to get you going is the `gke-uri` for your GKE clusters. 

    You can find the URI for each cluster via the following command:

    ```bash
    $ gcloud container clusters list --uri
    ```

    Confirm that the clusters are registered with Hub:

    ```bash
    $ gcloud container hub memberships list
    NAME        EXTERNAL_ID
    gke-blue    50468ae8-29a3-4ea1-b7ff-0e216533619a
    gke-green   6c2704d2-e499-465d-99d6-3ca1f3d8170b
    ```
    Confirm that the clusters are visible via MCS:

    ```bash
    $ gcloud alpha container hub multi-cluster-services describe
      createTime: '2021-04-14T04:13:52.419729923Z'
      featureState:
        detailsByMembership:
          projects/481193910697/locations/global/memberships/gke-blue:
            code: OK
            description: Firewall successfully updated
            updateTime: '2021-04-22T03:24:14.472913243Z'
          projects/481193910697/locations/global/memberships/gke-green:
            code: OK
            description: Firewall successfully updated
            updateTime: '2021-04-22T00:56:47.636992389Z'
        lifecycleState: ENABLED
      multiclusterservicediscoveryFeatureSpec: {}
      name: projects/am01-gateway-test/locations/global/features/multiclusterservicediscovery
      updateTime: '2021-04-14T04:13:53.541761063Z'
    ```

5. Now specify `gke-blue` as your config cluster.

    ```bash
    $ gcloud alpha container hub ingress enable \
      --config-membership=projects/${PROJECT}/locations/global/memberships/gke-blue
    ```

6. Confirm that MCI is configured properly.

    ```bash
    $ gcloud alpha container hub ingress describe
      createTime: '2021-04-14T04:19:30.536942953Z'
      featureState:
        details:
          code: OK
          description: Ready to use
        detailsByMembership:
          projects/481193910697/locations/global/memberships/gke-blue:
            code: OK
          projects/481193910697/locations/global/memberships/gke-green:
            code: OK
        lifecycleState: ENABLED
      multiclusteringressFeatureSpec:
        configMembership: projects/am01-gateway-test/locations/global/memberships/gke-blue
      name: projects/am01-gateway-test/locations/global/features/multiclusteringress
      updateTime: '2021-04-14T04:19:31.841415834Z'
    ```
7. Create the [proxy-only subnet](https://cloud.google.com/load-balancing/docs/l7-internal/proxy-only-subnets) and required firewall rules in your VPC for the internal Multi-cluster gateway

    > Note: for the CIDR range, select a range compatible with your environment

    ```bash
    $ gcloud compute networks subnets create proxy-only-subnet \
    --purpose=INTERNAL_HTTPS_LOAD_BALANCER \
    --role=ACTIVE \
    --region=us-west1 \
    --network=default \
    --range=10.6.240.0/23
    ```

    ```bash
    $ gcloud compute firewall-rules create fw-allow-proxies \
    --network=default \
    --action=allow \
    --direction=ingress \
    --source-ranges=10.6.240.0/23 \
    --rules=tcp:80,tcp:443,tcp:8080
    ```

8. Create the client VM

    ```bash
    $ gcloud compute instances create client-vm \
      --image-family=debian-9 \
      --image-project=debian-cloud \
      --network=default \
      --zone=us-west1-a \
      --tags=allow-ssh
    ```
