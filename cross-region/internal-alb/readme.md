## Cross Region Internal Application Load Balancer

This recipe provides a walkthrough to set up a cross region internal application load balancer with failover and health checks. For information about the load balancer refer: [Cross Region Internal Application Load Balancer](https://cloud.google.com/load-balancing/docs/l7-internal/setting-up-l7-cross-reg-hybrid).

Initial project configuration

```shell
gcloud config configurations create cross-region-alb
gcloud auth login --update-adc

export PROJECT_ID=cross-region-lb-sandbox
gcloud auth application-default set-quota-project cross-region-lb-sandbox
gcloud config set project cross-region-lb-sandbox
```

Enable required APIs

```shell
gcloud services enable \
    cloudresourcemanager.googleapis.com 
    compute.googleapis.com 
    container.googleapis.com
```

VPC Network setup

```shell
gcloud compute networks create mc-net --subnet-mode=custom --mtu=1450\
    --bgp-routing-mode=global

gcloud compute networks subnets create snet1 --range=192.168.0.0/20 \
    --stack-type=IPV4_ONLY --network=mc-net --region=us-central1 \
    --secondary-range=snet1-range1=6.0.0.0/20,snet1-range2=6.0.16.0/20 \
    --enable-private-ip-google-access

gcloud compute networks subnets create snet2 --range=192.168.16.0/20 \
    --stack-type=IPV4_ONLY --network=mc-net --region=us-east1 \
    --secondary-range=snet2-range1=6.0.32.0/20,snet2-range2=6.0.48.0/20 \
    --enable-private-ip-google-access

gcloud compute firewall-rules create iap-fw --direction=INGRESS \
    --priority=1000 --network=mc-net --action=ALLOW --rules=tcp:22 \
    --source-ranges=35.235.240.0/20
```

Create GKE clusters

```shell
gcloud iam service-accounts create gke-ap-sa
export GSA_EMAIL=gke-ap-sa@${PROJECT_ID}.iam.gserviceaccount.com

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member serviceAccount:${GSA_EMAIL} \
  --role roles/container.admin

gcloud container clusters create-auto "mc1" --region "us-central1" --release-channel "rapid" \
    --enable-private-nodes --enable-private-endpoint --master-ipv4-cidr "6.0.128.0/28" \
    --enable-master-authorized-networks --enable-master-global-access \
    --enable-master-global-access --master-authorized-networks 192.168.0.0/16 \
    --network "projects/${PROJECT_ID}/global/networks/mc-net" \
    --subnetwork "projects/${PROJECT_ID}/regions/us-central1/subnetworks/snet1" \
    --cluster-secondary-range-name "snet1-range1" --services-secondary-range-name "snet1-range2" \
    --service-account gke-ap-sa@${PROJECT_ID}.iam.gserviceaccount.com --scopes=cloud-platform --async

gcloud container clusters create-auto "mc2" --region "us-east1" --release-channel "rapid" \
    --enable-private-nodes --enable-private-endpoint --master-ipv4-cidr "6.0.128.16/28" \
    --enable-master-authorized-networks --enable-master-global-access --master-authorized-networks 192.168.0.0/16 \
    --network "projects/${PROJECT_ID}/global/networks/mc-net" \
    --subnetwork "projects/${PROJECT_ID}/regions/us-east1/subnetworks/snet2" --cluster-secondary-range-name "snet2-range1" \
    --services-secondary-range-name "snet2-range2" \
    --service-account gke-ap-sa@${PROJECT_ID}.iam.gserviceaccount.com --scopes=cloud-platform --async
```

Create a test instance in central region

```shell
gcloud compute instances create mc-test \
    --zone=us-central1-a \
    --machine-type=e2-small \
    --network-interface=stack-type=IPV4_ONLY,subnet=snet1,no-address \
    --maintenance-policy=MIGRATE \
    --provisioning-model=STANDARD \
    --service-account=gke-ap-sa@${PROJECT_ID}.iam.gserviceaccount.com \
    --scopes=https://www.googleapis.com/auth/cloud-platform \
  --create-disk=auto-delete=yes,boot=yes,device-name=mc-test,image=projects/debian-cloud/global/images/debian-11-bullseye-v20231004,mode=rw,size=10,type=projects/${PROJECT_ID}/zones/us-central1-a/diskTypes/pd-balanced \
    --shielded-secure-boot \
    --shielded-vtpm \
    --shielded-integrity-monitoring \
    --labels=goog-ec-src=vm_add-gcloud \
    --reservation-affinity=any
```

SSH into the test instance and install tools

```shell
gcloud compute ssh --zone "us-central1-a" "mc-test" --tunnel-through-iap
sudo apt-get install kubectl google-cloud-sdk-gke-gcloud-auth-plugin
```

Get cluster credentials

```shell
gcloud container clusters get-credentials mc1 --region us-central1
gcloud container clusters get-credentials mc2 --region us-east1

kubectl config rename-context gke_cross-region-lb-sandbox_us-central1_mc1 mc1
kubectl config rename-context gke_cross-region-lb-sandbox_us-east1_mc2 mc2
```

Deploy sample workloads

```shell
for i in 1 2; do kubectl --context mc${i} apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: whereami
  labels:
    app: whereami
spec:
  replicas: 3
  selector:
    matchLabels:
      app: whereami
  template:
    metadata:
      labels:
        app: whereami
    spec:
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: DoNotSchedule
      containers:
      - name: frontend
        image: us-docker.pkg.dev/google-samples/containers/gke/whereami:v1.2.20
        ports:
        - containerPort: 8080
EOF
done
```

Create the services

```shell
for i in 1 2; do kubectl --context mc${i} apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  labels:
    app: whereami
  annotations:
    cloud.google.com/neg: '{"exposed_ports": {"80":{"name": "whereami"}}}'
  name: whereami
spec:
  ports:
  - port: 80
    protocol: TCP
    targetPort: 8080
  selector:
    app: whereami
EOF
done
```

Create proxy subnets

```shell
gcloud beta compute networks subnets create proxy-snet1 \
        --purpose=GLOBAL_MANAGED_PROXY \
        --role=ACTIVE \
        --region=us-central1 \
        --network=mc-net \
        --range=6.0.144.0/24
    
gcloud beta compute networks subnets create proxy-snet2 \
        --purpose=GLOBAL_MANAGED_PROXY \
        --role=ACTIVE \
        --region=us-east1 \
        --network=mc-net \
        --range=6.0.145.0/24
```

Create firewall rules

```shell
gcloud compute firewall-rules create fw-allow-health-check \
    --network=mc-net \
    --action=allow \
    --direction=ingress \
    --source-ranges=130.211.0.0/22,35.191.0.0/16 \
    --rules=tcp:8080

gcloud compute firewall-rules create fw-allow-proxy-only-subnet \
    --network=mc-net \
    --action=allow \
    --direction=ingress \
    --source-ranges=6.0.144.0/24,6.0.145.0/24 \
    --rules=tcp:8080
```

Set up the load balancer

```shell
gcloud compute health-checks create http gil7-basic-check \
   --use-serving-port \
   --global

gcloud compute backend-services create whereami \
  --load-balancing-scheme=INTERNAL_MANAGED \
  --protocol=HTTP \
  --enable-logging \
  --logging-sample-rate=1.0 \
  --health-checks=gil7-basic-check \
  --global-health-checks \
  --global

for zone in $(gcloud container clusters describe mc1 --region us-central1 --format json | \
    jq -r .locations[]); do gcloud compute backend-services add-backend whereami   \
    --global   --balancing-mode=RATE   --max-rate-per-endpoint=1000 \
    --network-endpoint-group=whereami   --network-endpoint-group-zone=${zone}; done

for zone in $(gcloud container clusters describe mc2 --region us-east1 --format json | \
    jq -r .locations[]); do gcloud compute backend-services add-backend whereami   \
    --global   --balancing-mode=RATE   --max-rate-per-endpoint=1000 \
    --network-endpoint-group=whereami   --network-endpoint-group-zone=${zone}; done

gcloud compute url-maps create gil7-lb \
  --default-service=whereami \
  --global

gcloud compute target-http-proxies create gil7-http-proxy \
  --url-map=gil7-lb \
  --global

gcloud compute addresses create ip-central --region=us-central1 --subnet=snet1 --purpose=GCE_ENDPOINT

gcloud compute addresses create ip-east --region=us-east1 --subnet=snet2 --purpose=GCE_ENDPOINT

export IP_CENTRAL=$(gcloud compute addresses describe ip-central --region us-central1 --format json | jq -r .address)

export IP_EAST=$(gcloud compute addresses describe ip-east --region us-east1 --format json | jq -r .address)

gcloud compute forwarding-rules create gil7-fw-rule-central   --load-balancing-scheme=INTERNAL_MANAGED \
    --network=mc-net   --subnet=snet1   --subnet-region=us-central1   \
    --address=${IP_CENTRAL}  --ports=80   --target-http-proxy=gil7-http-proxy   --global

gcloud compute forwarding-rules create gil7-fw-rule-east   --load-balancing-scheme=INTERNAL_MANAGED \
    --network=mc-net   --subnet=snet2   --subnet-region=us-east1   \
    --address=${IP_EAST}  --ports=80   --target-http-proxy=gil7-http-proxy   --global
```

Configure DNS zone, this also enables health checking the backends for failover

```shell
gcloud dns managed-zones create cross-region-lb-internal --description="" \
    --dns-name="cross-region-lb.apps.internal." --visibility="private" \
    --networks="https://www.googleapis.com/compute/v1/projects/${PROJECT_ID}/global/networks/mc-net"

gcloud dns record-sets create whereami.cross-region-lb.apps.internal --ttl="30" \
    --type="A" --zone="cross-region-lb-internal" --routing-policy-type="GEO" \
    --routing-policy-data="us-central1=gil7-fw-rule-central@global;us-east1=gil7-fw-rule-east@global" \
    --enable-health-checking
```

Create a test instance in us-east1

```shell
gcloud compute instances create mc-test     --zone=us-east1-d     --machine-type=e2-small \
    --network-interface=stack-type=IPV4_ONLY,subnet=snet2,no-address  \
    --maintenance-policy=MIGRATE     --provisioning-model=STANDARD \
    --service-account=gke-ap-sa@${PROJECT_ID}.iam.gserviceaccount.com \
    --scopes=https://www.googleapis.com/auth/cloud-platform \
    --create-disk=auto-delete=yes,boot=yes,device-name=mc-test,image=projects/debian-cloud/global/images/debian-11-bullseye-v20231004,mode=rw,size=10,type=projects/${PROJECT_ID}/zones/us-east1-d/diskTypes/pd-balanced \
    --shielded-secure-boot     --shielded-vtpm     --shielded-integrity-monitoring \
    --labels=goog-ec-src=vm_add-gcloud     --reservation-affinity=any
```

Test GEO routing

Cloud DNS routes the requests to backends in respective regions

```shell
for zone in us-central1-a us-east1-d; do 
  gcloud compute ssh mc-test --zone ${zone} -- curl whereami.cross-region-lb.apps.internal; 
done
```

Test failover

The requests would failover to the central region since there are no healthy endpoints in east region

```shell
kubectl scale --replicas 0 deploy/whereami --context mc2
```

Clean up resources

```shell
gcloud container clusters delete mc1 --region us-central1
gcloud container clusters delete mc2 --region us-east1
for zone in us-central1-a us-east1-d; do 
  gcloud compute instances delete mc-test --zone ${zone}; 
done

gcloud dns record-sets delete whereami.cross-region-lb.apps.internal \
  --type="A" --zone="cross-region-lb-internal"
gcloud dns managed-zones delete cross-region-lb-internal

gcloud compute forwarding-rules delete gil7-fw-rule-central --global
gcloud compute forwarding-rules delete gil7-fw-rule-east --global
gcloud compute target-http-proxies delete gil7-http-proxy --global
gcloud compute url-maps delete gil7-lb --global

for zone in $(gcloud container clusters describe mc1 --region us-central1 --format json | \
    jq -r .locations[]); do gcloud compute backend-services remove-backend whereami   \
    --global --network-endpoint-group=whereami   --network-endpoint-group-zone=${zone}; done

for zone in $(gcloud container clusters describe mc2 --region us-east1 --format json | \
    jq -r .locations[]); do gcloud compute backend-services remove-backend whereami   \
    --global --network-endpoint-group=whereami   --network-endpoint-group-zone=${zone}; done

gcloud compute backend-services delete whereami --global
```


