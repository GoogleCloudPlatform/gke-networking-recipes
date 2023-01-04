# Set up environment variable

This will be referenced in upcoming command line examples.

```bash
  export PROJECT=$(gcloud config get-value project) # or your preferred project
```

## Enable the Kubernetes Engine API for your GCP project

  ```bash
  gcloud services enable container.googleapis.com
  ```

## Single-cluster environment

The single-cluster examples use the following GKE setup for deploying the manifests.  

```bash
  gcloud container clusters create gke-1 \
    --zone us-west1-a \
    --enable-ip-alias \
      --release-channel rapid 
```

## Multi-cluster environment basic

The multi-cluster examples use the following GKE setup for deploying the manifests. If you've already created `gke-1` in the [single Cluster Section](#single-cluster-environment), you can reuse that cluster.

1. Deploy two GKE clusters within your Google Cloud project.  

    Note: ```machine-type=e2-standard-4``` and ```num-nodes=4``` are used to support Anthos Service Mesh (ASM) deployment. You can use smaller machine-type and less number of nodes if ASM is not required. For more information about ASM minumum requirements for GKE, please [click here](https://cloud.google.com/service-mesh/v1.7/docs/scripted-install/gke-asm-onboard-1-7#requirements).

    ```bash
    gcloud container clusters create gke-1 \
    --machine-type=e2-standard-4 \
    --num-nodes=4 \
    --zone ${GKE1_ZONE} \
    --enable-ip-alias \
    --release-channel rapid \
    --workload-pool=${PROJECT}.svc.id.goog --async

    gcloud container clusters create gke-2 \
    --machine-type=e2-standard-4 \
    --num-nodes=4 \
    --zone ${GKE2_ZONE} \
    --enable-ip-alias \
    --release-channel rapid \
    --workload-pool=${PROJECT}.svc.id.goog --async
    ```

    Clusters creation takes around 5 min to complete

2. Ensure that the cluster is running:

    ```bash
    gcloud container clusters list
    ```

    The output is similar to the following, your regions might be different than the ones below:

    ```bash
    NAME   LOCATION       MASTER_VERSION   MASTER_IP      MACHINE_TYPE   NODE_VERSION     NUM_NODES  STATUS
    gke-1  us-central1-a  1.21.5-gke.1802  34.136.74.24   e2-standard-4  1.21.5-gke.1802  4          RUNNING
    gke-2  us-west1-b     1.21.5-gke.1802  35.233.255.33  e2-standard-4  1.21.5-gke.1802  4          RUNNING
    ```

3. Get the clusters credentials

    ```bash
    gcloud container clusters get-credentials gke-1 --zone $GKE1_ZONE
    gcloud container clusters get-credentials gke-2 --zone $GKE2_ZONE
    ```

4. Rename contexts

    The prior step will have added credentials for your new clusters to your `kubeconfig`, but let's rename the contexts to something a little shorter:

    ```bash
    kubectl config rename-context gke_${PROJECT}_${GKE1_ZONE}_gke-1 gke-1

    kubectl config rename-context gke_${PROJECT}_${GKE2_ZONE}_gke-2 gke-2
    ```

5. Enable the Hub, Anthos, and MultiClusterIngress APIs for your GCP project as described [here](https://cloud.google.com/kubernetes-engine/docs/how-to/ingress-for-anthos-setup#before_you_begin).

    ```bash
    gcloud services enable gkehub.googleapis.com

    gcloud services enable anthos.googleapis.com

    gcloud services enable multiclusteringress.googleapis.com
    ```

6. [Register](https://cloud.google.com/kubernetes-engine/docs/how-to/ingress-for-anthos-setup#registering_your_clusters) your two clusters (`gke-1` and `gke-2`).

    There are a few steps to complete as part of the registration process.

    Register the clusters with Hub.

    ```bash
    gcloud container hub memberships register gke-1 \
      --gke-cluster ${GKE1_ZONE}/gke-1 \
      --enable-workload-identity

     gcloud container hub memberships register gke-2 \
      --gke-cluster ${GKE2_ZONE}/gke-2 \
      --enable-workload-identity
    ```

    Confirm that they are registered with Hub. Your EXTERNAL_ID values might be different.

    ```bash
       gcloud container hub memberships list
    ```

    The output is similar to the following:

    ```bash
       NAME   EXTERNAL_ID
       gke-1  50468ae8-29a3-4ea1-b7ff-0e216533619a
       gke-2  6c2704d2-e499-465d-99d6-3ca1f3d8170b
    ```

7. Now enable Multi-cluster Ingress and specify `gke-1` as your config cluster.

    ```bash
    gcloud container hub ingress enable \
      --config-membership=projects/${PROJECT}/locations/global/memberships/gke-1
    ```

8. Confirm that MCI is configured properly.

    ```bash
    gcloud container hub ingress describe
    ```

    The output is similar to the following:

    ```bash
    createTime: '2021-01-14T09:09:57.475070502Z'
    membershipStates:
      projects/349736299228/locations/global/memberships/gke-1:
        state:
          code: OK
          updateTime: '2021-10-27T15:10:44.499214418Z'
      projects/349736299228/locations/global/memberships/gke-2:
        state:
          code: OK
          updateTime: '2021-10-27T15:10:44.499215578Z'
    name: projects/gke-net-recipes/locations/global/features/multiclusteringress
    resourceState:
      state: ACTIVE
    spec:
      multiclusteringress:
        configMembership: projects/gke-net-recipes/locations/global/memberships/gke-1
    state:
      state:
        code: OK
        description: Ready to use
        updateTime: '2021-10-27T15:09:33.451139409Z'
    updateTime: '2021-01-14T09:09:59.186872460Z'
    ```
  
9. At this stage your clusters for MCI are ready, you can return to the tutorial you started with.
  
## Multi-cluster environment blue/green

To implement the `multi-cluster-blue-green-cluster` pattern, we need another GKE cluster in the same region as `gke-1`. This section builds on the [previous section](#multi-cluster-environment-basic), and assumes you still have those clusters up and running.

1. Deploy another GKE cluster to the `us-west1` region (same region as `gke-1`, but a different zone)

    ```bash
    gcloud container clusters create gke-3 \
      --zone us-west1-b \
      --enable-ip-alias \
      --release-channel rapid
    ```

2. Rename context

    ```bash
       kubectl config rename-context gke_${PROJECT}_us-west1-b_gke-3 gke-3
    ```

3. [Register](https://cloud.google.com/kubernetes-engine/docs/how-to/ingress-for-anthos-setup#registering_your_clusters) `gke-3`, following the same steps used previously.

    Again, figuring out the `gke-uri` of a given cluster can be tricky, so use:

    ```bash
       gcloud container clusters list --uri
    ```

    Confirm registration of your clusters.

    ```bash
      gcloud container hub memberships list
    ```

    The output is similar to the following:

    ```bash
      NAME   EXTERNAL_ID
      gke-3  8187e1cd-35e8-41e1-b204-8ac5c7c7a240
      gke-2  47081e57-c326-4fa0-b808-7a7652863d32
      gke-1  90eeb089-cd16-4281-85ce-e724953249dc
    ```

## Multi-cluster environment (multi-cluster-services)

In order to use Multi-cluster services, following steps need to be completed to enable feature after you complete "Multi-cluster environment (basic)" set up.

1. Enable the CloudDNS, Traffic Director, MultiClusterServiceDiscovery APIs for your GCP project as described [here](https://cloud.google.com/kubernetes-engine/docs/how-to/multi-cluster-services#before_you_begin).

    ```bash
      gcloud services enable dns.googleapis.com

      gcloud services enable trafficdirector.googleapis.com

      gcloud services enable cloudresourcemanager.googleapis.com

      gcloud services enable multiclusterservicediscovery.googleapis.com
    ```

2. Now enable Multi-cluster Services.

    ```bash
       gcloud alpha container hub multi-cluster-services enable
    ```

3. Confirm that MCS is configured properly.

    ```bash
       gcloud alpha container hub multi-cluster-services describe
    ```

4. Grant required Identity to MCS Importer.

    ```bash
       gcloud projects add-iam-policy-binding ${PROJECT} \
        --member "serviceAccount:${PROJECT}.svc.id.goog[gke-mcs/gke-mcs-importer]" \
        --role "roles/compute.networkViewer"
    ```
