#!/bin/bash

# Pre-requisites:
# Install AWS CLI: https://aws.amazon.com/cli
# Configure profile for AWS CLI:
# $ aws configure --profile <profile_name>
# Install AWS IAM Authenticator:
# $ brew install aws-iam-authenticator
# Install Kubectl:
# $ brew install kubectl
# Install envsubst command:
# $ brew install gettext
# $ echo 'export PATH="/usr/local/opt/gettext/bin:$PATH"' >> ~/.bash_profile

# Prep variables
export AWS_PROFILE="profile_name"
export CLUSTER_NAME="cluster_name"
export REGION="us-east-1"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --profile ${AWS_PROFILE} --output text --query 'Account')

# Select EKS cluster
eksctl utils write-kubeconfig --profile ${AWS_PROFILE} --cluster ${CLUSTER_NAME} --region ${REGION}
kubectl get nodes

# Create IAM user ci-cd
aws iam create-user --profile ${AWS_PROFILE} --user-name ci-cd

# Create KubernetesCiCd IAM role
cat k8s/KubernetesCiCdRole.json | envsubst > k8s/KubernetesCiCdRole.final.json
aws iam create-role --profile ${AWS_PROFILE} --role-name KubernetesCiCd --description "CI/CD role recognized by the cluster and given adequate permissions to introspect and deploy" --assume-role-policy-document file://k8s/KubernetesCiCdRole.final.json --output text --query 'Role.Arn'
rm k8s/KubernetesCiCdRole.final.json

# Create IAM group ci-cd
aws iam create-group --profile ${AWS_PROFILE} --group-name ci-cd

# Create policy to allow assuming KubernetesCiCd IAM role
cat k8s/assume-KubernetesCiCdRole.json | envsubst > k8s/assume-KubernetesCiCdRole.final.json
aws iam create-policy --profile ${AWS_PROFILE} --policy-name assume-KubernetesCiCdRole --policy-document file://k8s/assume-KubernetesCiCdRole.final.json
rm k8s/assume-KubernetesCiCdRole.final.json

# Attach the policy to the group, along with other policies that allow control of EKS
aws iam attach-group-policy --profile ${AWS_PROFILE} --group-name ci-cd --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/assume-KubernetesCiCdRole
aws iam attach-group-policy --profile ${AWS_PROFILE} --group-name ci-cd --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
aws iam attach-group-policy --profile ${AWS_PROFILE} --group-name ci-cd --policy-arn arn:aws:iam::aws:policy/AmazonEKSServicePolicy
aws iam attach-group-policy --profile ${AWS_PROFILE} --group-name ci-cd --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
aws iam attach-group-policy --profile ${AWS_PROFILE} --group-name ci-cd --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser
aws iam attach-group-policy --profile ${AWS_PROFILE} --group-name ci-cd --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
aws iam attach-group-policy --profile ${AWS_PROFILE} --group-name ci-cd --policy-arn arn:aws:iam::aws:policy/CloudFrontFullAccess

# Add the IAM user to the group
aws iam add-user-to-group --profile ${AWS_PROFILE} --group-name ci-cd --user-name ci-cd

# Create k8s Role for ci-cd
kubectl apply -f k8s/cicd-role.yaml

# Create k8s RoleBinding for ci-cd
kubectl apply -f k8s/cicd-rolebinding.yaml

# Modify aws-auth ConfigMap to associate the IAM role KubernetesCiCd with k8s User ci-cd-role
kubectl get configmap aws-auth -n kube-system -o yaml | sed "/  mapRoles: |/a \ \ \ \ - rolearn: arn:aws:iam::${AWS_ACCOUNT_ID}:role\/KubernetesCiCd\n\ \ \ \ \ \ username: ci-cd-role" > new-aws-auth-configmap.yaml
kubectl apply -f new-aws-auth-configmap.yaml
rm new-aws-auth-configmap.yaml

# Finally, set local kube config to use aws-iam-authenticator
export CLUSTER_ENDPOINT=$(aws eks describe-cluster --name ${CLUSTER_NAME} --profile ${AWS_PROFILE} --region ${REGION} --output text --query 'cluster.endpoint')
export CERTIFICATE_AUTHORITY_DATA=$(aws eks describe-cluster --name ${CLUSTER_NAME} --profile ${AWS_PROFILE} --region ${REGION} --output text --query 'cluster.certificateAuthority.data')
cat k8s/kubeconfig-cicd.yaml | envsubst > k8s/kubeconfig-cicd.final.yaml
echo export KUBECONFIG=$(pwd)/k8s/kubeconfig-cicd.final.yaml >> ~/.bash_profile  # all future shell sessions
export KUBECONFIG=$(pwd)/k8s/kubeconfig-cicd.final.yaml
