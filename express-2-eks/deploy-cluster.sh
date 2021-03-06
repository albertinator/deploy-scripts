#!/bin/bash

# Pre-requisites:
# Install jq
# $ brew install jq
# Install AWS CLI: https://aws.amazon.com/cli
# Configure profile for AWS CLI:
# $ aws configure --profile <profile-name>
# Install AWS IAM authenticator:
# $ brew install aws-iam-authenticator
# Install eksctl:
# $ brew tap weaveworks/tap
# $ brew install weaveworks/tap/eksctl
# Install Kubectl:
# $ brew install kubectl
# Install Helm client
# $ curl -o get_helm.sh https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get
# $ chmod +x get_helm.sh
# $ ./get_helm.sh
# Install envsubst command:
# $ brew install gettext
# $ echo 'export PATH="/usr/local/opt/gettext/bin:$PATH"' >> ~/.bash_profile

# Prep variables
export AWS_PROFILE="profile_name"
export CLUSTER_NAME="cluster_name"
export REGION="us-east-1"
export ZONES="${REGION}a,${REGION}b,${REGION}d,${REGION}f"  # avoid c and e where m5 instances are not available
export NODE_TYPE="m5.large"
export DOMAIN="api.domain.com"

# NAT gateway/router (optional but recommended)
export USE_NAT="true"
export NAT_ZONES="${REGION}a,${REGION}b"  # Do the minimum 2 zones because HighlyAvailable NAT means IP in each AZ

# Make Kube API endpoint private behind VPC (highly recommended)
export KUBE_PRIVATE_ENDPOINT="true"

# Restricting public Kube API access (if Kube endpoint public, this is recommended)
export RESTRICT_API="true"
export OFFICE_IP="12.34.56.78"
export VPN_IP="87.65.43.21"
export CI_RUNNER_IP="14.23.58.67"
export MASTER_AUTHORIZED_NETWORKS="${OFFICE_IP}/32,${VPN_IP}/32,${CI_RUNNER_IP}/32"

# create EKS cluster
export CLUSTER_STATUS=$(eksctl get cluster --profile ${AWS_PROFILE} --region ${REGION} --name ${CLUSTER_NAME} > /dev/null 2>&1 && echo OK || echo FAILED)
if [ "$CLUSTER_STATUS" = "FAILED" ]  # only if cluster doesn't already exist
then
  if [ "$USE_NAT" = "true" ]
  then
    echo "$(tput setaf 2)with NAT gateway...$(tput sgr0)"
    eksctl create cluster \
      --profile ${AWS_PROFILE} \
      --region ${REGION} \
      --name ${CLUSTER_NAME} \
      --zones ${NAT_ZONES} \
      --node-type ${NODE_TYPE} \
      --ssh-access \
      --node-private-networking \
      --vpc-nat-mode HighlyAvailable
  else
    eksctl create cluster \
      --profile ${AWS_PROFILE} \
      --region ${REGION} \
      --name ${CLUSTER_NAME} \
      --zones ${ZONES} \
      --node-type ${NODE_TYPE} \
      --ssh-access
  fi
  echo "$(tput setaf 2)Created cluster $(tput setab 4)${CLUSTER_NAME}$(tput sgr0)"

  if [ "$RESTRICT_API" = "true" ]
  then
    echo "$(tput setaf 2)Restricting Kubernetes public API for cluster ${CLUSTER_NAME} to ${MASTER_AUTHORIZED_NETWORKS}...$(tput sgr0)"
    eksctl utils set-public-access-cidrs \
      --approve \
      --profile ${AWS_PROFILE} \
      --cluster=${CLUSTER_NAME} \
      ${MASTER_AUTHORIZED_NETWORKS}
  fi
fi

# Select EKS cluster
eksctl utils write-kubeconfig --profile ${AWS_PROFILE} --cluster ${CLUSTER_NAME} --region ${REGION}
kubectl get nodes

# Install Tiller (if doesn't exist)
export TILLER_STATUS="$(kubectl get serviceaccount -n kube-system tiller > /dev/null 2>&1 && echo OK || echo FAILED)"
if [ "$TILLER_STATUS" != "OK" ]
then
  echo "$(tput setaf 2)Setting up Tiller...$(tput sgr0)"
  kubectl create serviceaccount -n kube-system tiller
  kubectl create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
  helm init --service-account tiller
fi
kubectl get deployments -n kube-system tiller-deploy

# wait until Tiller is running before next step
while [ "$TILLER_RUNNING_STATUS" != "OK" ]
do
  export TILLER_RUNNING_STATUS="$(kubectl get pods -n kube-system | grep tiller-deploy | grep Running > /dev/null 2>&1 && echo OK || echo FAILED)"
  sleep 10
done

# Install Nginx Ingress Controller (if doesn't exist)
export NGINX_INGRESS_CTRLR_STATUS="$(kubectl get deployment nginx-ingress-controller nginx-ingress-default-backend -n nginx-ingress > /dev/null 2>&1 && echo OK || echo FAILED)"
if [ "$NGINX_INGRESS_CTRLR_STATUS" != "OK" ]
then
  echo "$(tput setaf 2)Setting up Nginx Ingress Controller...$(tput sgr0)"
  kubectl create namespace nginx-ingress
  helm install --name nginx-ingress --namespace nginx-ingress stable/nginx-ingress --set rbac.create=true -f k8s/nginx-values.yaml
fi
kubectl get deployments -n nginx-ingress
kubectl get svc -n nginx-ingress

# Install Cert Manager (if doesn't exist)
export CERT_MANAGER_CTRLR_STATUS="$(kubectl get deployment cert-manager -n cert-manager > /dev/null 2>&1 && echo OK || echo FAILED)"
if [ "$CERT_MANAGER_CTRLR_STATUS" != "OK" ]
then
  echo "$(tput setaf 2)Setting up Certificate Manager Controller...$(tput sgr0)"
  kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v1.0.2/cert-manager.yaml
  kubectl create namespace cert-manager
  kubectl label namespace cert-manager certmanager.k8s.io/disable-validation=true
  helm repo add jetstack https://charts.jetstack.io
  helm repo update
  helm init --upgrade
  helm install --name cert-manager --namespace cert-manager --version v1.0.2 jetstack/cert-manager --set installCRDs=true --set webhook.enabled=false  # webhook.enabled=false needs to be set for private clusters, but not necessary for public clusters. if necessary, delete cert-manager and re-install with this flag
  cat k8s/issuer.yaml | envsubst | kubectl apply -f -
fi
kubectl get deployments -n cert-manager
kubectl get issuers -n cert-manager

export PROMETHEUS_CTRLR_STATUS="$(kubectl get deployment prometheus-prometheus-oper-operator -n monitoring > /dev/null 2>&1 && echo OK || echo FAILED)"
if [ "$PROMETHEUS_CTRLR_STATUS" != "OK" ]
then
  echo "$(tput setaf 2)Setting up Prometheus/Grafana monitoring...$(tput sgr0)"
  kubectl create namespace monitoring
  helm install stable/prometheus-operator --name prometheus --namespace monitoring
fi
kubectl get deployments -n monitoring

echo "$(tput setaf 2)Cluster ${CLUSTER_NAME} is all set!$(tput sgr0)"

# Set DNS A or CNAME record to point to Nginx Ingress controller IP (get via `kubectl get svc -n nginx-ingress`)

# Whitelist on external services the static IP address for NAT (look at NAT Gateway in AWS console)

if [ "$KUBE_PRIVATE_ENDPOINT" = "true" ]
then
  echo "$(tput setaf 2)Make Kubernetes API endpoint private behind VPC for cluster ${CLUSTER_NAME}$(tput sgr0)"
  aws eks update-cluster-config \
    --profile ${AWS_PROFILE} \
    --name ${CLUSTER_NAME} \
    --region ${REGION} \
    --resources-vpc-config endpointPublicAccess=false,endpointPrivateAccess=true
fi
