#!/bin/bash

# Install AWS CLI: https://aws.amazon.com/cli
# Configure profile for AWS CLI:
# $ aws configure --profile <profile-name>

export AWS_PROFILE="profile_name"
export CLUSTER_NAME="cluster_name"

# create key pair
aws ec2 create-key-pair \
  --profile ${AWS_PROFILE} \
  --key-name ${CLUSTER_NAME}-bastion \
  --query 'KeyMaterial' \
  --output text > ${CLUSTER_NAME}-bastion.pem
chmod 400 ${CLUSTER_NAME}-bastion.pem

# get cluster VPC ID
export VPC_ID=$(
  aws ec2 describe-vpcs \
    --profile ${AWS_PROFILE} \
    --filters "Name=tag:alpha.eksctl.io/cluster-name,Values=${CLUSTER_NAME}" \
    --query 'Vpcs[0].VpcId' \
    --output text
)

# get all existing security groups for this VPC whose name includes the cluster name
export CLUSTER_SGS=$(
  aws ec2 describe-security-groups \
    --profile ${AWS_PROFILE} \
    --filters "Name=vpc-id,Values=${VPC_ID}" "Name=group-name,Values=*${CLUSTER_NAME}*" \
    --query 'SecurityGroups[*].GroupId' \
    --output text
)

# create security group
export SG_ID=$(
  aws ec2 create-security-group \
   --profile ${AWS_PROFILE} \
   --description "Launch SG for ${CLUSTER_NAME}-bastion" \
   --group-name launch-${CLUSTER_NAME}-bastion \
   --vpc-id ${VPC_ID} \
   --query 'GroupId' \
   --output text
)

# add inbound rule to security group
# for opening SSH (TCP port 22), allowing only current IP
aws ec2 authorize-security-group-ingress \
  --group-id ${SG_ID} \
  --protocol tcp \
  --port 22 \
  --cidr $(curl checkip.amazonaws.com)/32

# get a public subnet ID in the VPC
export SUBNET_ID=$(
  aws ec2 describe-subnets \
    --profile ${AWS_PROFILE} \
    --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=*Public*" \
    --query 'Subnets[0].SubnetId' \
    --output text
)

export INSTANCE_ID=$(
  aws ec2 run-instances \
    --profile ${AWS_PROFILE} \
    --image-id ami-0a0ddd875a1ea2c7f \
    --count 1 \
    --instance-type t2.micro \
    --key-name ${CLUSTER_NAME}-bastion \
    --security-group-ids ${SG_ID} ${CLUSTER_SGS} \
    --subnet-id ${SUBNET_ID} \
    --associate-public-ip-address \
    --user-data file://bastion-setup.sh \
    --query 'Instances[0].InstanceId' \
    --output text
)

# get PublicDnsName from running instance
export PUBLIC_DNS_NAME=$(
  aws ec2 describe-instances \
    --profile ${AWS_PROFILE} \
    --instance-ids ${INSTANCE_ID} \
    --query 'Reservations[0].Instances[0].PublicDnsName' \
    --output text
)

echo $PUBLIC_DNS_NAME
# ssh -i ${CLUSTER_NAME}-bastion.pem ubuntu@${PUBLIC_DNS_NAME}
