# Express Web API to Google Kubernetes Engine (GKE)

The architecture of this Kubernetes deployment is designed with the following assumptions:
* That an NGINX Ingress controller running in cluster can itself sufficiently handle requests without the help of an external Network Load Balancer
* That you intend to serve API requests over HTTPS only, and that Let's Encrypt is a sufficient authority for your situation

If any of these assumptions are not true, it is possible to extend this setup to accomodate the additional requirement(s). Those instructions are beyond the scope of this more simple setup.

**NOTE**: the cluster as deployed in `deploy-cluster.sh` also includes a custom network on which a NAT router is deployed. This makes it such that all egress (outgoing) traffic from the cluster is translated to a single static IP address, making it possible to whitelist that NAT IP address to secure external services. If you would like to deploy without a NAT router, just remove the lines that reference the NAT router variables. Otherwise, the static IP address to whitelist can be found by running:
```bash
$ gcloud compute addresses list
```

**NOTE**: the cluster as deployed in `deploy-cluster.sh` also restricts access to Kubernetes master to a few IP addresses (explicitly listed in `MASTER_AUTHORIZED_NETWORKS`). If you would like to deploy without this restriction, simply remove the `gcloud container clusters update` line.

## Cloud Services used
* Google Kubernetes Engine (GKE)
* Google Cloud NAT
* Google Container Registry (GCR)
* Let's Encrypt Certificate Authority

## Pre-requisites

1. Install Gettext (`envsubst` command)
```bash
$ brew install gettext
$ echo 'export PATH="/usr/local/opt/gettext/bin:$PATH"' >> ~/.bash_profile
```

2. Install Google Cloud SDK
* [https://cloud.google.com/sdk/docs/quickstarts](https://cloud.google.com/sdk/docs/quickstarts)

3. Configure Google Cloud Profile
```bash
$ gcloud auth login
```

4. Install `kubectl`
```bash
$ gcloud components install kubectl
```

5. Install `helm`
```bash
$ curl -o get_helm.sh https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get
$ chmod +x get_helm.sh
$ ./get_helm.sh
```

## Usage

Copy all files in this directory to the root of your Express Web API app. Then open both `deploy-cluster.sh` and `deploy.sh` and replace the following variables at the top:

<table>
  <tr>
    <td><strong>Variable name</strong></td>
    <td><strong>Requirement</strong></td>
    <td><strong>Description</strong></td>
  </tr>

  <tr>
    <td>PROJECT_ID</td>
    <td>Required</td>
    <td>This is needed by the naming convention for Docker images in the Google Container Registry. Choose from available projects listed in <a href="https://console.cloud.google.com/projectselector2/home/dashboard" target="_blank">Google Cloud Dashboard</a></td>
  </tr>

  <tr>
    <td>CLUSTER_NAME</td>
    <td>Required</td>
    <td>The name of your cluster. You can name this anything you want.</td>
  </tr>

  <tr>
    <td>VM_ID</td>
    <td>Required (<code>deploy.sh</code> only)</td>
    <td>The name of your app. You can name this anything you want, but you should aim for this name to describe your app in a short word because it will be used to name all Kubernetes objects (deployment, service, ingress, secret, etc).
  </tr>

  <tr>
    <td>REGION</td>
    <td>Required (<code>deploy-cluster.sh</code> only)</td>
    <td>The Google Cloud region you'd like to use for this deployment. This is used to determine where the Kubernetes cluster will be deployed.</td>
  </tr>

  <tr>
    <td>ZONE</td>
    <td>Required</td>
    <td>The Google Cloud zone you'd like to use for this deployment. This is used to determine where the Kubernetes cluster will be deployed.</td>
  </tr>

  <tr>
    <td>VERSION</td>
    <td>Do not modify (<code>deploy.sh</code> only)</td>
    <td>The version by default will update itself based on your Git repository's most recent commit SHA. Only modify this if you have a better version assignment scheme.</td>
  </tr>

  <tr>
    <td>NODE_TYPE</td>
    <td>Required (<code>deploy-cluster.sh</code> only)</td>
    <td>The class and size of the Google Cloud instances to be used as nodes in this Kubernetes cluster (ex: <code>n1-standard-1</code>).</td>
  </tr>

  <tr>
    <td>DOMAIN</td>
    <td>Required</td>
    <td>The domain of your API deployment. This will be used as the basis for the SSL certificate generated by the Cert Manager.</td>
  </tr>
</table>

**NOTE**: for any variable name found in *both* `deploy.sh` and `deploy-cluster.sh`, the corresponding values MUST be equivalent across both files.

Then check these files into your repository.

To deploy your cluster on GKE:
```bash
$ ./deploy-cluster.sh
```

Then set your domain's DNS record (A or CNAME) to this cluster's NGINX Ingress' external IP:
```bash
$ kubectl get svc -n nginx-ingress
NAME                            TYPE           CLUSTER-IP      EXTERNAL-IP     PORT(S)                      AGE
nginx-ingress-controller        LoadBalancer   10.31.254.118   35.225.12.49   80:32101/TCP,443:32504/TCP   1d
```
This must be done **before** you run `deploy.sh` because when the Ingress is first deployed, the Cert Manager challenge used to issue the SSL certificate is done by polling your domain's DNS entry.

Create your secrets manifest:
```bash
$ cp k8s/deployment-secret.yaml.sample k8s/deployment-secret.yaml
```

Add this resulting file to your `.gitignore`:
```bash
$ echo k8s/deployment-secret.yaml >> .gitignore
```

For each variable in the secrets manifest, fill in the Base 64 encoded string:
```bash
$ echo -n <raw string> | base64
```
Don't forget to use the `-n` flag, otherwise the secrets will include a newline character which will be interpreted literally.

If you want to **add** a new variable to the secrets manifest to be used, be sure to update `deployment.yaml` with another entry in the `spec.template.spec.containers[].env` array:
```bash
spec:
  ...
  template:
    ...
    spec:
      containers:
      ...
      - ...
        ...
        env:
        ...
        - name: "NEW_VAR"
          valueFrom:
            secretKeyRef:
              name: deployment-secret
              key: NEW_VAR
```

Finally, to deploy the app from the command line, run:
```bash
$ ./deploy.sh
```
