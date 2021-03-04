#!/bin/bash

# Pre-requisites:
# Install doctl:
# $ brew install doctl
# Install Kubectl:
# $ brew install kubectl
# Install Helm client
# $ curl -o get_helm.sh https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get
# $ chmod +x get_helm.sh
# $ ./get_helm.sh
# Install envsubst command:
# $ brew install gettext
# $ echo 'export PATH="/usr/local/opt/gettext/bin:$PATH"' >> ~/.bash_profile

# Login
doctl auth init

# Prep variables
export CLUSTER_NAME="cluster_name"
export REGION="sfo2"
export NODE_TYPE="s-1vcpu-2gb"
export DOMAIN="api.domain.com"

# create DOKS cluster
export CLUSTER_STATUS="$(doctl kubernetes cluster get ${CLUSTER_NAME} > /dev/null 2>&1 && echo OK || echo FAILED)"
if [ "$CLUSTER_STATUS" != "OK" ]
then
  echo "$(tput setaf 2)Creating cluster ${CLUSTER_NAME}...$(tput sgr0)"
  doctl kubernetes cluster create ${CLUSTER_NAME} \
    --region ${REGION} \
    --count 2 \
    --size ${NODE_TYPE}
  echo "$(tput setaf 2)Created cluster $(tput setab 4)${CLUSTER_NAME}$(tput sgr0)"
fi
doctl kubernetes cluster list

# Select DOKS cluster
doctl kubernetes cluster kubeconfig save ${CLUSTER_NAME}
kubectl get nodes

# Make sure cluster can use the container registry
doctl kubernetes cluster registry add ${CLUSTER_NAME}

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
