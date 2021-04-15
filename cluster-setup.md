## Set up environment variable

This will be referenced in upcoming command line examples.

```bash
$ export PROJECT=$(gcloud config get-value project) # or your preferred project
```


## Single-cluster environment

The single-cluster examples use the following GKE setup for deploying the manifests.

```bash
$ gcloud container clusters create gke-1 \
	--zone us-west1-a \
	--enable-ip-alias \
  	--release-channel rapid 
```


## Multi-cluster environment (basic)

The multi-cluster examples use the following GKE setup for deploying the manifests. If you've already created `gke-1` in the [single-cluster section](#), you can reuse that cluster.

1. Deploy two GKE clusters within your Google Cloud project.

    ```bash
    $ gcloud container clusters create gke-1 \
      --zone us-west1-a \
      --enable-ip-alias \
      --release-channel rapid \
      --workload-pool=${PROJECT}.svc.id.goog

    $ gcloud container clusters create gke-2 \
      --zone us-east1-b \
      --enable-ip-alias \
      --release-channel rapid \
      --workload-pool=${PROJECT}.svc.id.goog
    ```

2. Rename contexts

    The prior step will have added credentials for your new clusters to your `kubeconfig`, but let's rename the contexts to something a little shorter:

    ```bash

    $ kubectl config rename-context gke_${PROJECT}_us-west1-a_gke-1 gke-1

    $ kubectl config rename-context gke_${PROJECT}_us-east1-b_gke-2 gke-2
    ```

3. Enable the Hub, Anthos, and MultiClusterIngress APIs for your GCP project as described [here](https://cloud.google.com/kubernetes-engine/docs/how-to/ingress-for-anthos-setup#before_you_begin).

    ```bash

    $ gcloud services enable gkehub.googleapis.com

    $ gcloud services enable anthos.googleapis.com

    $ gcloud services enable multiclusteringress.googleapis.com
    ```

4. [Register](https://cloud.google.com/kubernetes-engine/docs/how-to/ingress-for-anthos-setup#registering_your_clusters) your two clusters (`gke-1` and `gke-2`). 

    There are a few steps to complete as part of the registration process. A quick hint to get you going is the `gke-uri` for your GKE clusters. 

    You can find the URI for each cluster via the following command:

    ```bash
    $ gcloud container clusters list --uri
    ```

    Confirm that they are registered with Hub.

    ```
    $ gcloud container hub memberships list
    NAME   EXTERNAL_ID
    gke-1  50468ae8-29a3-4ea1-b7ff-0e216533619a
    gke-2  6c2704d2-e499-465d-99d6-3ca1f3d8170b
    ```

5. Now enable Multi-cluster Ingress and specify `gke-1` as your config cluster.

    ```bash
    $ gcloud alpha container hub ingress enable \
      --config-membership=projects/${PROJECT}/locations/global/memberships/gke-1
    ```

6. Confirm that MCI is configured properly.

    ```bash
    $ gcloud alpha container hub ingress describe
    createTime: '2020-08-16T05:15:32.127012063Z'
    featureState:
      details:
        code: OK
        description: Ready to use
      detailsByMembership:
        projects/1050705688268/locations/global/memberships/gke-1:
          code: OK
      hasResources: true
      lifecycleState: ENABLED
    multiclusteringressFeatureSpec:
      configMembership: projects/alexmattson-ifa-081520-0404/locations/global/memberships/i4a-us-central1-01
    name: projects/alexmattson-ifa-081520-0404/locations/global/features/multiclusteringress
    updateTime: '2020-08-16T05:15:33.464612511Z'
    ```

## Multi-cluster environment (blue-green cluster)

To implement the `multi-cluster-blue-green-cluster` pattern, we need another GKE cluster in the same region as `gke-1`. This section builds on the [previous section](#multi-cluster-environment-basic), and assumes you still have those clusters up and running.

1. Deploy another GKE cluster to the `us-west1` region (same region as `gke-1`, but a different zone)

    ```bash
    $ gcloud container clusters create gke-3 \
      --zone us-west1-b \
      --enable-ip-alias \
      --release-channel rapid
    ```

2. Rename context

    ```bash
    $ kubectl config rename-context gke_${PROJECT}_us-west1-b_gke-3 gke-3
    ```

3. [Register](https://cloud.google.com/kubernetes-engine/docs/how-to/ingress-for-anthos-setup#registering_your_clusters) `gke-3`, following the same steps used previously.

    Again, figuring out the `gke-uri` of a given cluster can be tricky, so use:

    ```bash
    $ gcloud container clusters list --uri
    ```

    Confirm registration of your clusters.
    ```
    $ gcloud container hub memberships list
    NAME   EXTERNAL_ID
    gke-3  8187e1cd-35e8-41e1-b204-8ac5c7c7a240
    gke-2  47081e57-c326-4fa0-b808-7a7652863d32
    gke-1  90eeb089-cd16-4281-85ce-e724953249dc
    ```


## Multi-cluster environment (multi-cluster-services)

In order to use Multi-cluster services, following steps need to be completed to enable feature after you complete "Multi-cluster environment (basic)" set up.

1. Enable the CloudDNS, Traffic Director, MultiClusterServiceDiscovery APIs for your GCP project as described [here](https://cloud.google.com/kubernetes-engine/docs/how-to/multi-cluster-services#before_you_begin).

    ```bash

    $ gcloud services enable dns.googleapis.com

    $ gcloud services enable trafficdirector.googleapis.com

    $ gcloud services enable cloudresourcemanager.googleapis.com

    $ gcloud services enable multiclusterservicediscovery.googleapis.com
    ```

2. Now enable Multi-cluster Services.

    ```bash
    $ gcloud alpha container hub multi-cluster-services enable
    ```

3. Confirm that MCS is configured properly.

    ```bash
    $gcloud alpha container hub multi-cluster-services describe
    ```

4. Grant required Identity to MCS Importer.

    ```bash
    $gcloud projects add-iam-policy-binding ${PROJECT} \
     --member "serviceAccount:${PROJECT}.svc.id.goog[gke-mcs/gke-mcs-importer]" \
     --role "roles/compute.networkViewer"
    ```
