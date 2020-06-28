# CI/CD to Amazon Elastic Kubernetes Service (EKS)

An example configuration of a CI/CD script for deploying to EKS. Additionally, these scripts illustrate how to create a special IAM user `ci-cd` that is only limited to EKS administration in AWS, connected to a Kubernetes RBAC role with limited privileges in the cluster.

## Cloud Services used
* AWS Elastic Kubernetes Service (EKS)
* Gitlab CI/CD

## Pre-requisites

Make sure the cluster is already created from running `deploy-cluster.sh`.

Also deploy `Dockerfile.eks-deploy` to Docker Hub. This contains all the necessary command line tools for deployment, which the CI/CD script will use on several steps:
```bash
$ docker build -t org_name/eks-deploy -f Dockerfile.eks-deploy
$ docker login
$ docker push org_name/eks-deploy
```

## Usage

Copy all files in this directory to the root of your Express Web API app. Then open both `deploy-cicd-user.sh` and `.gitlab-ci.yml` and replace the following variables at the top:

<table>
  <tr>
    <td><strong>Variable name</strong></td>
    <td><strong>Requirement</strong></td>
    <td><strong>Description</strong></td>
  </tr>

  <tr>
    <td>AWS_PROFILE</td>
    <td>Required</td>
    <td>The name of the profile you used in <code>aws configure --profile profile_name</code></td>
  </tr>

  <tr>
    <td>AWS_ACCOUNT_ID</td>
    <td>Do not modify (<code>deploy.sh</code> only)</td>
    <td>This is needed by the naming convention for Docker images in the AWS Elastic Container Registry. This can be found in your <a href="https://console.aws.amazon.com/iam" target="_blank">IAM dashboard</a>. This should be retrieved via <code>aws</code> command.</td>
  </tr>

  <tr>
    <td>CLUSTER_NAME</td>
    <td>Required</td>
    <td>The name of your cluster. You can name this anything you want.</td>
  </tr>

  <tr>
    <td>VM_ID</td>
    <td>Required</td>
    <td>The name of your app. You can name this anything you want, but you should aim for this name to describe your app in a short word because it will be used to name all Kubernetes objects (deployment, service, ingress, secret, etc).
  </tr>

  <tr>
    <td>REGION</td>
    <td>Required</td>
    <td>The AWS region you'd like to use for this deployment. This is used to determine where the Kubernetes cluster will be deployed.</td>
  </tr>
</table>

**NOTE**: for any variable name found in *both* `deploy-cicd-user.sh` and `.gitlab-ci.yml`, the corresponding values MUST be equivalent across both files.

Then check all files into your repository.

To deploy your IAM user `ci-cd` on EKS and create the Kubernetes user, role, and rolebinding:
```bash
$ ./deploy-cicd-user.sh
```

Now get the Access Key ID and Secret Access Key for the `ci-cd` IAM user and enter that into the global environment variables in the CI/CD vendor system:
* AWS_ACCESS_KEY_ID
* AWS_SECRET_ACCESS_KEY

Finally, push to the remote that kicks off the CI/CD process:
```bash
$ git push origin branches/branch-x
```
