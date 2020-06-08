#!/bin/bash

# Pre-requisites:
# Install AWS CLI
# Set up "profile_name" AWS CLI config profile:
# $ aws configure --profile ${AWS_PROFILE}
# Install zip
# Install jq
# $ npm install jq -g
# Install envsubst command:
# $ brew install gettext
# $ echo 'export PATH="/usr/local/opt/gettext/bin:$PATH"' >> ~/.bash_profile

export AWS_PROFILE="profile_name"
export BUCKET="bucket_name"
export REGION="us-east-1"
export LAMBDA_ROLE="basic_lambda_role"
export LAMBDA_FUNCTION="url-rewrite-function"
export CNAME_ALIAS="www.domain.com"  # if no custom domain, leave this blank
export SSL_CERT_DOMAIN="*.domain.com"  # if no custom domain, leave this blank

# Build
rm -rf public/
rm -rf .cache/
npx gatsby build

export BUCKET_EXISTS=$(aws s3 ls s3://${BUCKET} --profile ${AWS_PROFILE} > /dev/null 2>&1 && echo OK || echo FAILED)
if [ "$BUCKET_EXISTS" = "FAILED" ]
then
  aws s3 mb s3://${BUCKET} --profile ${AWS_PROFILE}
  aws s3 website s3://${BUCKET} --index-document index.html --error-document 404.html --profile ${AWS_PROFILE}
  echo "$(tput setaf 2)Created S3 bucket: $(tput setab 4)${BUCKET}$(tput sgr0)"
fi

echo "$(tput setaf 2)Syncing local files with S3 bucket...$(tput sgr0)"
cd public
aws s3 sync --profile ${AWS_PROFILE} --acl public-read --sse --delete ./ s3://${BUCKET}
cd ../

export ROLE_EXISTS=$(aws iam get-role --profile ${AWS_PROFILE} --role-name ${LAMBDA_ROLE} > /dev/null 2>&1 && echo OK || echo FAILED)
if [ "$ROLE_EXISTS" = "FAILED" ]
then
  aws iam create-role --profile ${AWS_PROFILE} --role-name ${LAMBDA_ROLE} --assume-role-policy-document file://deploy/${LAMBDA_ROLE}.json
  sleep 10  # give the role some time to be ready to be used
  echo "$(tput setaf 2)Created basic Lambda role: $(tput setab 4)${LAMBDA_ROLE}$(tput sgr0)"
fi
export ROLE_ARN=$(aws iam get-role --profile ${AWS_PROFILE} --role-name ${LAMBDA_ROLE} | jq -r '.Role.Arn')
echo "$(tput setaf 2)Retrieved basic Lambda role ARN: $(tput setab 4)${ROLE_ARN}$(tput sgr0)"

export FUNCTION_EXISTS=$(aws lambda get-function --profile ${AWS_PROFILE} --function-name ${LAMBDA_FUNCTION} --region ${REGION} > /dev/null 2>&1 && echo OK || echo FAILED)
if [ "$FUNCTION_EXISTS" = "FAILED" ]
then
  cd deploy
  zip function.zip urlrewrite.js
  aws lambda create-function --profile ${AWS_PROFILE} --function-name ${LAMBDA_FUNCTION} --region ${REGION} --zip-file fileb://function.zip --handler urlrewrite.handler --runtime nodejs10.x --role ${ROLE_ARN}
  rm function.zip
  cd ../
  echo "$(tput setaf 2)Created Lambda function: $(tput setab 4)${LAMBDA_FUNCTION}$(tput sgr0)"
fi
export FUNCTION_ARN=$(aws lambda get-function --profile ${AWS_PROFILE} --function-name ${LAMBDA_FUNCTION} --region ${REGION} | jq -r '.Configuration.FunctionArn')
echo "$(tput setaf 2)Retrieved Lambda function ARN: $(tput setab 4)${FUNCTION_ARN}$(tput sgr0)"

export LATEST_VERSION=$(aws lambda list-versions-by-function --profile ${AWS_PROFILE} --function-name ${LAMBDA_FUNCTION} --region ${REGION} | jq -r '.Versions[-1].Version')
if [ "$LATEST_VERSION" = "\$LATEST" ]
then
  export LATEST_VERSION=$(aws lambda publish-version --profile ${AWS_PROFILE} --function-name ${LAMBDA_FUNCTION} --region ${REGION} | jq -r '.Version')
  echo "$(tput setaf 2)Published latest version of function ${LAMBDA_FUNCTION}: $(tput setab 4)${LATEST_VERSION}$(tput sgr0)"
fi
echo "$(tput setaf 2)Retrieved Lambda function latest version: $(tput setab 4)${LATEST_VERSION}$(tput sgr0)"

export SSL_CERT_ARN=$(aws acm list-certificates --profile ${AWS_PROFILE} --region ${REGION} | jq -r '.CertificateSummaryList[] | select(.DomainName == "'${SSL_CERT_DOMAIN}'") | .CertificateArn')
if [ -z "$SSL_CERT_ARN" ]
then
  # Create SSL cert
  export SSL_CERT_ARN=$(aws acm request-certificate --profile ${AWS_PROFILE} --domain-name ${SSL_CERT_DOMAIN} --validation-method EMAIL --region ${REGION} | jq -r '.CertificateArn')
  echo "$(tput setaf 2)Created ACM certificate: $(tput setab 4)${SSL_CERT_ARN} for ${SSL_CERT_DOMAIN}$(tput sgr0)"
  echo "$(tput setaf 2)DO NOT PROCEED until you CHECK your ${SSL_CERT_DOMAIN} e-mail to approve certificate generation$(tput sgr0)"
  read -p "Once you approve and certificate is valid, press any key to continue... " -n1 -s
fi
echo "$(tput setaf 2)Retrieved ACM certificate: $(tput setab 4)${SSL_CERT_ARN} for ${SSL_CERT_DOMAIN}$(tput sgr0)"

export DISTRIBUTION_ID=$(aws cloudfront list-distributions --profile ${AWS_PROFILE} | jq -r '.DistributionList.Items[] | select(.Origins.Items[-1].Id == "S3-'${BUCKET}'") | .Id')
if [ -z "$DISTRIBUTION_ID" ]
then
  # Create distribution
  cat deploy/dist-config-$([ -z "$CNAME_ALIAS" ] && echo "cloudfront" || echo "custom").json | envsubst > deploy/dist-config.final.json
  export DISTRIBUTION_ID=$(aws cloudfront create-distribution --profile ${AWS_PROFILE} --distribution-config file://deploy/dist-config.final.json | jq -r '.Distribution.Id')
  mv deploy/dist-config.final.json distribution.log
  echo "$(tput setaf 2)Created Cloudfront distribution: $(tput setab 4)${DISTRIBUTION_ID}$(tput sgr0)"
else
  # Update distribution Lambda ARN
  # * call GetDistributionConfig to get current configuration
  # * make edits to add or update the Lambda function trigger (as identified by FUNCTION_ARN:LATEST_VERSION)
  # * call UpdateDistribution to update the configuration if the function ARN or version are different

  # Invalidate Cloudfront CDN distribution
  aws configure set preview.cloudfront true --profile ${AWS_PROFILE}
  aws cloudfront create-invalidation --profile ${AWS_PROFILE} --distribution-id ${DISTRIBUTION_ID} --paths '/*'
  echo "$(tput setaf 2)Created cache invalidation for Cloudfront distribution: $(tput setab 4)${DISTRIBUTION_ID}$(tput sgr0)"
fi

if test -z "$CNAME_ALIAS"
then
  export DISTRIBUTION_URL=$(aws cloudfront list-distributions --profile ${AWS_PROFILE} | jq -r '.DistributionList.Items[] | select(.Origins.Items[-1].Id == "S3-'${BUCKET}'") | .DomainName')
  echo "$(tput setaf 2)Found Cloudfront URL: $(tput setab 4)${DISTRIBUTION_URL}$(tput sgr0)"
  open http://${DISTRIBUTION_URL}
else
  open $(test -z "$SSL_CERT_ARN" && echo "http" || echo "https")://${CNAME_ALIAS}
fi
