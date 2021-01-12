#!/bin/bash

# Pre-requisites:
# Install AWS CLI: https://aws.amazon.com/cli
# Configure profile for AWS CLI:
# $ aws configure --profile profile_name
# Install eksctl:
# $ brew tap weaveworks/tap
# $ brew install weaveworks/tap/eksctl
# Install Kubectl:
# $ brew install kubectl
# Install envsubst command:
# $ brew install gettext
# $ echo 'export PATH="/usr/local/opt/gettext/bin:$PATH"' >> ~/.bash_profile

# Prep variables
export AWS_PROFILE="profile_name"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --profile ${AWS_PROFILE} --output text --query 'Account')
export CLUSTER_NAME="cluster_name"
export VM_ID="app_name"
export REGION="us-east-1"
export VERSION="$(git rev-parse --short HEAD)"
export DOMAIN="api.domain.com"
export IMAGE_NAME=${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${VM_ID}:${VERSION}

# Select EKS cluster
eksctl utils write-kubeconfig --profile ${AWS_PROFILE} --cluster ${CLUSTER_NAME} --region ${REGION}
kubectl get nodes

# Create repository in ECR registry
export REPOSITORY_STATUS=$(aws ecr describe-repositories --profile ${AWS_PROFILE} | jq '.repositories | .[] | select(.repositoryName=="'${VM_ID}'")')
if [ "$REPOSITORY_STATUS" = "" ]  # only if repository doesn't already exist
then
  aws ecr create-repository --repository-name ${VM_ID} --profile ${AWS_PROFILE}
  echo "$(tput setaf 2)Created repository $(tput setab 4)${VM_ID}$(tput sgr0)"
fi

# Build and upload app image to registry
export IMAGE_TAG_STATUS=$(aws ecr list-images --profile ${AWS_PROFILE} --repository-name ${VM_ID} | jq '.imageIds | .[] | select (.imageTag=="'${VERSION}'")')
if [ "$IMAGE_TAG_STATUS" = "" ]  # only if image tag doesn't already exist
then
  docker build -t ${IMAGE_NAME} .
  `aws ecr get-login --profile ${AWS_PROFILE} --region ${REGION} --no-include-email`
  docker push ${IMAGE_NAME}
  echo "$(tput setaf 2)Pushed image to ECR Container Registry: $(tput setab 4)${IMAGE_NAME}$(tput sgr0)"
fi

echo "$(tput setaf 2)Applying all ENV secrets for deployment...$(tput sgr0)"
cat k8s/deployment-secret.yaml | envsubst | kubectl apply -f -
kubectl get secrets

echo "$(tput setaf 2)Applying deployment ${VM_ID}...$(tput sgr0)"
cat k8s/deployment.yaml | envsubst | kubectl apply -f -
kubectl get deployments

echo "$(tput setaf 2)Applying service (of type NodePort) ${VM_ID}...$(tput sgr0)"
cat k8s/service.yaml | envsubst | kubectl apply -f -
kubectl get services

echo "$(tput setaf 2)Applying ingress for NodePort ${VM_ID}...$(tput sgr0)"
cat k8s/ingress.yaml | envsubst | kubectl apply -f -
kubectl get ingress

# Check
open https://${DOMAIN}
