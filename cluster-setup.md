## Environment setup

The following cluster configuration can be used for the single-cluster networking examples in this repo.

```bash
$ gcloud container clusters create gke-1 \
	--zone us-west1-a \
	--enable-ip-alias \
  --release-channel rapid 
```



