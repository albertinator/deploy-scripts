#!/bin/bash

# Pre-requisites:
# Install doctl:
# $ brew install doctl
# Install Kubectl:
# $ brew install kubectl
# Install envsubst command:
# $ brew install gettext
# $ echo 'export PATH="/usr/local/opt/gettext/bin:$PATH"' >> ~/.bash_profile

# Login
doctl auth init

# Prep variables
export REGISTRY="registry_name"
export CLUSTER_NAME="cluster_name"
export VM_ID="image_name"
export REGION="sfo2"
export VERSION="$(git rev-parse --short HEAD)"
export DOMAIN="api.domain.com"

# Select DOKS cluster
doctl kubernetes cluster kubeconfig save ${CLUSTER_NAME}
kubectl get nodes

# Build and upload image to DigitalOcean Container Registry
doctl registry login
export IMAGE_STATUS="$(doctl registry repository list-tags ${VM_ID} --format Tag --no-header | grep ^${VERSION}$ > /dev/null 2>&1 && echo OK || echo FAILED)"
if [ "$IMAGE_STATUS" = "FAILED" ]  # only if image doesn't already exist
then
  docker build -t registry.digitalocean.com/${REGISTRY}/${VM_ID}:${VERSION} .
  docker push registry.digitalocean.com/${REGISTRY}/${VM_ID}:${VERSION}
  echo "$(tput setaf 2)Pushed image to DigitalOcean Container Registry: $(tput setab 4)registry.digitalocean.com/${REGISTRY}/${VM_ID}:${VERSION}$(tput sgr0)"
fi

echo "$(tput setaf 2)Applying all ENV secrets for deployment...$(tput sgr0)"
cat k8s/deployment-secret.yaml | envsubst | kubectl apply -f -
kubectl get secrets

echo "$(tput setaf 2)Applying API deployment ${VM_ID}...$(tput sgr0)"
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
