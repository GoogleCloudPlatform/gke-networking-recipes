# Google Cloud Armor enabled ingress

Following recipe provides a walk-through for setting up [GKE Ingress](https://cloud.google.com/kubernetes-engine/docs/concepts/ingress)
with [Google Cloud Armor](https://cloud.google.com/armor) protection.

Google Cloud Armor protects your applications and websites against denial of service and web attacks.
Since GKE Ingresses use **proxy-based** [Google Cloud HTTP(s) Load Balancers](https://cloud.google.com/load-balancing/docs/https),
**protection against L3 and L4 DDos attacks is enabled by default**.

Applications can be also protected with Layer7 filtering by using Google Cloud Armor
[security policies](https://cloud.google.com/armor/docs/security-policy-overview). Once Google Cloud
Armor security policy is configured, it can be used to protect services associated with a given ingress.

## Use cases

* Protect backend services at the networking edge with Layer7 filtering rules

## Relevant documentation

* [Cloud Armor overview](https://cloud.google.com/armor)
* [Cloud Armor security policy](https://cloud.google.com/armor/docs/security-policy-overview)
* [GKE ingress overview](https://cloud.google.com/kubernetes-engine/docs/concepts/ingress)

## Versions & Compatibility

* GKE version 1.19.10+ *(for GA of this feature)*
* Works with [External Ingress](https://cloud.google.com/kubernetes-engine/docs/how-to/load-balance-ingress)
  *(single-cluster)*
* Tested and validated with GKE version 1.19.10 on Jul 2nd 2021

---

![cloudarmor-ingress](../../../images/cloudarmor-ingress.png)

Google Cloud Armor protection is integrated with ingress for GKE by leveraging [BackendConfig CRD](https://github.com/kubernetes/ingress-gce/tree/master/pkg/apis/backendconfig).
This object is associated with a given service and allows to specify configuration for HTTPs Load Balancer
that handles incoming traffic. Google Cloud Armor policy can be can be enabled for a service by specifying
`securityPolicy` block with `name` key that defines name of the policy that will be applied.

**NOTE**: GKE creates [default backend](https://cloud.google.com/kubernetes-engine/docs/concepts/ingress#default_backend)
service upon cluster creation. This default service returns `404` HTTP response code and is used
on any Ingress as a default destination for unmatched requests - unless `defaultBackend` field with custom
service is specified. Keep in mind that **GKE default backend service has no associated `BackendConfig`
by default**, so you need to configure CloudArmor policy for it explicitly.

**NOTE**: applying `cloud.google.com/backend-config` annotation on an existing service, that is 
associated with an existing Ingress, makes no changes on underlying backend service.
Refer to [following issue for details](https://github.com/kubernetes/ingress-gce/issues/1503).

## Walk-through

Prerequisites:

* GKE cluster up and running *(check [Prerequisite: GKE setup](#prerequisite-gke-setup) below)*
* Google Cloud Armor policy configured *(check [Configuring Google Cloud Armor security policies](https://cloud.google.com/armor/docs/configure-security-policies)
  guide)*

Steps:

1. (Optional) Enable Google CloudArmor policy on a `default-http-backend` service

   * Create `BackendConfig` in a `kube-system` namespace. Substitute example policy name with your
   CloudArmor policy name

     ```sh
     cat << EOF | kubectl apply -f - -n kube-system
     apiVersion: cloud.google.com/v1
     kind: BackendConfig
     metadata:
       name: cloudarmor-test
     spec:
       securityPolicy:
         name: cloudarmor-test
     EOF
     ```

   * Annotate `default-http-backend` service in a `kube-system` namespace with a newly created `BackendConfig`

     ```sh
     kubectl annotate services default-http-backend \
     beta.cloud.google.com/backend-config='{"default": "cloudarmor-test"}' -n kube-system
     ```

2. Replace `$POLICY_NAME` variable in `cloudarmor-ingress.yaml` file with your Google CloudArmor
policy name.

   ```sh
   sed -i '.bak' 's/$POLICY_NAME/cloudarmor-test/g' cloudarmor-ingress.yaml
   ```

3. Apply `cloudarmor-ingress.yaml` file

   ```sh
   $ kubectl apply -f cloudarmor-ingress.yaml
   ingress.networking.k8s.io/cloudarmor-test created
   backendconfig.cloud.google.com/cloudarmor-test created
   service/whereami created
   deployment.apps/whereami created
   $
   ```

4. Wait until all created objects reach desired state

5. Verify and enjoy

### Prerequisite: GKE setup

1. Enable GKE API

   ```sh
   gcloud services enable container.googleapis.com
   ```

2. Create simple zonal GKE cluster for tests

   ```sh
   gcloud container clusters create cluster-test \
   --zone europe-central2-a \
   --release-channel regular \
   --enable-ip-alias
   ```

3. Configure client credentials for a new cluster

   ```sh
   gcloud container clusters get-credentials cluster-test \
   --zone europe-central2-a
   ````
