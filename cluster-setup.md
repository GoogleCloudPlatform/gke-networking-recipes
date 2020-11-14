## Single-cluster environment

The single-cluster examples use the following GKE setup for deploying the manifests.

```bash
$ gcloud container clusters create gke-1 \
	--zone us-west1-a \
	--enable-ip-alias \
  	--release-channel rapid 
```


## Multi-cluster environment

The multi-cluster examples use the following GKE setup for deploying the manifests.

1. Deploy two GKE clusters within your Google Cloud project.

```bash
$ gcloud container clusters create gke-1 \
	--zone us-west1-a \
	--enable-ip-alias \
 	--release-channel rapid 

$ gcloud container clusters create gke-2 \
	--zone us-east1-a \
	--enable-ip-alias \
  --release-channel rapid 
```

2. Enable the Hub, Anthos, and MultiClusterIngress APIs as done [here](https://cloud.google.com/kubernetes-engine/docs/how-to/ingress-for-anthos-setup#before_you_begin).
3. [Register](https://cloud.google.com/kubernetes-engine/docs/how-to/ingress-for-anthos-setup#registering_your_clusters) your two clusters. Confirm that they are registered with Hub.

```
$ gcloud container hub memberships list
NAME   EXTERNAL_ID
gke-1  50468ae8-29a3-4ea1-b7ff-0e216533619a
gke-2  6c2704d2-e499-465d-99d6-3ca1f3d8170b
```

4. Now enable Multi-cluster Ingress and specify `gke-1` as your config cluster.

```bash
$ gcloud alpha container hub ingress enable \
  --config-membership=projects/<your-project>/locations/global/memberships/gke-1
```

5. Confirm that MCI is configured properly.

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

