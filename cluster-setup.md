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
 	--release-channel rapid 

$ gcloud container clusters create gke-2 \
	--zone us-east1-b \
	--enable-ip-alias \
  --release-channel rapid 
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

4. [Register](https://cloud.google.com/kubernetes-engine/docs/how-to/ingress-for-anthos-setup#registering_your_clusters) your two clusters. Confirm that they are registered with Hub.

```
$ gcloud container hub memberships list
NAME   EXTERNAL_ID
gke-1  50468ae8-29a3-4ea1-b7ff-0e216533619a
gke-2  6c2704d2-e499-465d-99d6-3ca1f3d8170b
```

5. Now enable Multi-cluster Ingress and specify `gke-1` as your config cluster.

```bash
$ gcloud alpha container hub ingress enable \
  --config-membership=projects/<your-project>/locations/global/memberships/gke-1
```

6. Confirm that MCI is configured properly.

```bash
$ gcloud alpha container hub ingress describe
createTime: '2020-11-14T20:50:53.856780163Z'
featureState:
  details:
    code: OK
    description: Ready to use
  detailsByMembership:
    projects/759444700240/locations/global/memberships/gke-1:
      code: OK
    projects/759444700240/locations/global/memberships/gke-2:
      code: OK
  hasResources: true
  lifecycleState: ENABLED
multiclusteringressFeatureSpec:
  configMembership: projects/church-243723/locations/global/memberships/gke-1
name: projects/church-243723/locations/global/features/multiclusteringress
updateTime: '2020-11-14T20:50:54.761389487Z'
```

## Multi-cluster environment (blue-green cluster)

To implement the `multi-cluster-blue-green-cluster` pattern, we need another GKE cluster in the same region as `gke-1`.

1. Deploy another GKE cluster to `us-west1-a`

```bash
$ gcloud container clusters create gke-3 \
	--zone us-west1-a \
	--enable-ip-alias \
 	--release-channel rapid 
```