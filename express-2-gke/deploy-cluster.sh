#!/bin/bash

# Pre-requisites:
# Install Google Cloud SDK: https://cloud.google.com/sdk/docs/quickstarts
# Install Kubectl:
# $ gcloud components install kubectl
# Install Helm client
# $ curl -o get_helm.sh https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get
# $ chmod +x get_helm.sh
# $ ./get_helm.sh
# Install envsubst command:
# $ brew install gettext
# $ echo 'export PATH="/usr/local/opt/gettext/bin:$PATH"' >> ~/.bash_profile

# Login
gcloud auth login

# Prep variables
export PROJECT_ID="$(gcloud config get-value project -q)"
export CLUSTER_NAME="cluster_name"
export REGION="us-central1"
export ZONE="${REGION}-c"
export NODE_TYPE="n1-standard-1"
export DOMAIN="api.domain.com"

# NAT gateway/router (optional but recommended)
export USE_NAT="true"
export CUSTOM_NETWORK="${CLUSTER_NAME}-custom-network"
export SUBNET="subnet-${REGION}-192"
export STATIC_IP_NAME="${CLUSTER_NAME}-static-ip"
export ROUTER_NAME="nat-router"
export ROUTER_CONFIG_NAME="nat-config"

# Restricting Kube API access (optional but recommended)
export RESTRICT_API="true"
export OFFICE_IP="12.34.56.78"
export VPN_IP="87.65.43.21"
export CI_RUNNER_IP="14.23.58.67"
export MASTER_AUTHORIZED_NETWORKS="${OFFICE_IP}/32,${VPN_IP}/32,${CI_RUNNER_IP}/32"

# Set the project
gcloud config set project ${PROJECT_ID}

if [ "$USE_NAT" = "true" ]
then
  # create custom network and subnet if not exist
  export CUSTOM_NETWORK_STATUS="$(gcloud compute networks describe ${CUSTOM_NETWORK} > /dev/null 2>&1 && echo OK || echo FAILED)"
  if [ "$CUSTOM_NETWORK_STATUS" != "OK" ]
  then
    echo "$(tput setaf 2)Creating custom network ${CUSTOM_NETWORK} and subnet ${SUBNET}...$(tput sgr0)"
    gcloud compute networks create ${CUSTOM_NETWORK} --subnet-mode custom
    gcloud compute networks subnets create ${SUBNET} --network ${CUSTOM_NETWORK} --region ${REGION} --range 192.168.1.0/24
  fi
  gcloud compute networks list
  gcloud compute networks subnets list --network ${CUSTOM_NETWORK}
fi

# create GKE cluster
export CLUSTER_STATUS="$(gcloud container clusters describe ${CLUSTER_NAME} --zone ${ZONE} > /dev/null 2>&1 && echo OK || echo FAILED)"
if [ "$CLUSTER_STATUS" != "OK" ]
then
  echo "$(tput setaf 2)Creating cluster ${CLUSTER_NAME}...$(tput sgr0)"
  if [ "$USE_NAT" = "true" ]
  then
    echo "$(tput setaf 2)with NAT gateway...$(tput sgr0)"
    gcloud container clusters create ${CLUSTER_NAME} \
      --zone ${ZONE} \
      --username admin \
      --cluster-version latest \
      --machine-type ${NODE_TYPE} \
      --image-type "COS" \
      --disk-type "pd-standard" \
      --disk-size "100" \
      --scopes "https://www.googleapis.com/auth/compute","https://www.googleapis.com/auth/devstorage.read_only","https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring","https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly","https://www.googleapis.com/auth/trace.append" \
      --num-nodes 2 \
      --enable-cloud-logging \
      --enable-cloud-monitoring \
      --enable-private-nodes \
      --master-ipv4-cidr "172.16.0.0/28" \
      --enable-ip-alias \
      --network "projects/${PROJECT_ID}/global/networks/${CUSTOM_NETWORK}" \
      --subnetwork "projects/${PROJECT_ID}/regions/${REGION}/subnetworks/${SUBNET}" \
      --max-nodes-per-pool 110 \
      --addons HorizontalPodAutoscaling,HttpLoadBalancing,KubernetesDashboard \
      --enable-autoupgrade \
      --enable-autorepair
  else
    gcloud container clusters create ${CLUSTER_NAME} \
      --zone ${ZONE}
      --num-nodes 2 \
      --enable-cloud-logging \
      --enable-cloud-monitoring \
      --addons HorizontalPodAutoscaling,HttpLoadBalancing,KubernetesDashboard \
      --enable-autoupgrade \
      --enable-autorepair
  fi
  echo "$(tput setaf 2)Created cluster $(tput setab 4)${CLUSTER_NAME}$(tput sgr0)"

  if [ "$RESTRICT_API" = "true" ]
  then
    echo "$(tput setaf 2)Restricting Kubernetes API for cluster ${CLUSTER_NAME} to ${MASTER_AUTHORIZED_NETWORKS}...$(tput sgr0)"
    gcloud container clusters update ${CLUSTER_NAME} \
      --zone ${ZONE} \
      --enable-master-authorized-networks \
      --master-authorized-networks ${MASTER_AUTHORIZED_NETWORKS}
  fi
fi
gcloud container clusters list

if [ "$USE_NAT" = "true" ]
then
  # create static IP for NAT router
  export STATIC_IP_STATUS="$(gcloud compute addresses describe ${STATIC_IP_NAME} --region ${REGION} > /dev/null 2>&1 && echo OK || echo FAILED)"
  if [ "$STATIC_IP_STATUS" != "OK" ]
  then
    echo "$(tput setaf 2)Creating static IP ${STATIC_IP_NAME}...$(tput sgr0)"
    gcloud compute addresses create ${STATIC_IP_NAME} --region ${REGION}
  fi
  gcloud compute addresses list

  # create NAT router and config if not exist
  export ROUTER_STATUS="$(gcloud compute routers describe ${ROUTER_NAME} --region ${REGION} > /dev/null 2>&1 && echo OK || echo FAILED)"
  if [ "$ROUTER_STATUS" != "OK" ]
  then
    echo "$(tput setaf 2)Creating router ${ROUTER_NAME} and config ${ROUTER_CONFIG_NAME}...$(tput sgr0)"
    gcloud compute routers create ${ROUTER_NAME} \
      --network ${CUSTOM_NETWORK} \
      --region ${REGION}
    gcloud compute routers nats create ${ROUTER_CONFIG_NAME} \
      --router-region ${REGION} \
      --router ${ROUTER_NAME} \
      --nat-external-ip-pool=${STATIC_IP_NAME} \
      --nat-all-subnet-ip-ranges
  fi
  gcloud compute routers list
  gcloud compute routers nats list --router ${ROUTER_NAME} --router-region ${REGION}
fi

# Install Tiller (if doesn't exist)
export TILLER_STATUS="$(kubectl get serviceaccount --namespace kube-system tiller > /dev/null 2>&1 && echo OK || echo FAILED)"
if [ "$TILLER_STATUS" != "OK" ]
then
  echo "$(tput setaf 2)Setting up Tiller...$(tput sgr0)"
  kubectl create serviceaccount --namespace kube-system tiller
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

# Whitelist on external services the static IP address for NAT (run `gcloud compute addresses list` to find it)
