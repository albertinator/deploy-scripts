#!/bin/bash

# Script to set up Bastion host within VPC
# with kubectl and eksctl commands
# This script is run as root when passed to `aws ec2 run-instances`

export CLUSTER_NAME="cluster_name"
export REGION="us-east-1"

apt update

apt install -y awscli
aws configure

# install aws-iam-authenticator
curl -o aws-iam-authenticator https://amazon-eks.s3.us-west-2.amazonaws.com/1.17.7/2020-07-08/bin/linux/amd64/aws-iam-authenticator
chmod +x ./aws-iam-authenticator
mkdir -p $HOME/bin && cp ./aws-iam-authenticator $HOME/bin/aws-iam-authenticator && export PATH=$PATH:$HOME/bin
echo 'export PATH=$PATH:$HOME/bin' >> ~/.bashrc
aws-iam-authenticator help

# install aws v2 if not already
apt install -y unzip
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install

# install eksctl
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
mv /tmp/eksctl /usr/local/bin
eksctl version

# install kubectl
curl -o kubectl https://amazon-eks.s3.us-west-2.amazonaws.com/1.17.7/2020-07-08/bin/linux/amd64/kubectl
chmod +x ./kubectl
mv ./kubectl /usr/local/bin
kubectl version --short --client

# ask user to enter AWS credentials upon login to SSH session (also wipe prev credentials)
runuser -l ubuntu -c 'echo rm -rf ~/.aws >> ~/.bashrc'
runuser -l ubuntu -c 'echo rm -rf ~/.kube >> ~/.bashrc'
runuser -l ubuntu -c 'echo aws configure >> ~/.bashrc'
runuser \
  -l ubuntu \
  -c 'echo eksctl utils write-kubeconfig --cluster '${CLUSTER_NAME}' --region '${REGION}' >> ~/.bashrc'

# securely delete AWS and Kube credentials upon logout from SSH session
runuser -l ubuntu -c 'echo rm -rf ~/.aws >> ~/.bash_logout'
runuser -l ubuntu -c 'echo rm -rf ~/.kube >> ~/.bash_logout'

# securely delete AWS and Kube credentials every 15 mins (in case .bash_logout is not invoked)
echo "*/15 * * * * rm -rf ~/.aws" >> ubuntu
echo "*/15 * * * * rm -rf ~/.kube" >> ubuntu
chmod 600 ubuntu
chown ubuntu:crontab ubuntu
mv ubuntu /var/spool/cron/crontabs/ubuntu
