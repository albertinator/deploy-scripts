#!/bin/bash

# Pre-requisites:
# Install Google Cloud SDK: https://cloud.google.com/sdk/docs/quickstarts
# Install Kubectl:
# $ gcloud components install kubectl
# Install envsubst command:
# $ brew install gettext
# $ echo 'export PATH="/usr/local/opt/gettext/bin:$PATH"' >> ~/.bash_profile

# Login
gcloud auth login

# Prep variables
export PROJECT_ID="$(gcloud config get-value project -q)"
export CLUSTER_NAME="cluster_name"
export VM_ID="app_name"
export ZONE="us-central1-c"
export VERSION="$(git rev-parse --short HEAD)"
export DOMAIN="api.domain.com"

# Set the project
gcloud config set project ${PROJECT_ID}

# Select GKE cluster
gcloud container clusters get-credentials ${CLUSTER_NAME} --zone ${ZONE}
kubectl get nodes

# Build and upload image to Google Cloud
export IMAGE_STATUS="$(gcloud container images describe gcr.io/${PROJECT_ID}/${VM_ID}:${VERSION} > /dev/null 2>&1 && echo OK || echo FAILED)"
if [ "$IMAGE_STATUS" = "FAILED" ]  # only if image doesn't already exist
then
  docker build -t gcr.io/${PROJECT_ID}/${VM_ID}:${VERSION} .
  gcloud docker -- push gcr.io/${PROJECT_ID}/${VM_ID}:${VERSION}
  echo "$(tput setaf 2)Pushed image to Google Cloud Registry: $(tput setab 4)gcr.io/${PROJECT_ID}/${VM_ID}:${VERSION}$(tput sgr0)"
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
