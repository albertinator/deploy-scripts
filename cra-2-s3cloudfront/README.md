# Create React App to S3/Cloudfront

The Create React App build process will generate a set of static files. This script places those static files in S3 as objects and then creates a Cloudfront distribution that uses the S3 bucket as a source. S3 serves its role as a reliable object store, while Cloudfront provides services for handling web requests such as CDN edge caching and invalidation, gzip compression, serving an SSL certificate, forcing a redirect to HTTPS, invoking a Lambda function upon each request, writing to logs, doing special HTTP routing, etc.

## Cloud Services used
* AWS S3
* AWS Cloudfront
* AWS Lambda
* AWS Certificate Manager

## Pre-requisites

1. Install Zip, JQ, Gettext
```bash
$ brew install zip jq gettext
$ echo 'export PATH="/usr/local/opt/gettext/bin:$PATH"' >> ~/.bash_profile
```

2. Install AWS CLI
```bash
$ curl "https://s3.amazonaws.com/aws-cli/awscli-bundle.zip" -o "awscli-bundle.zip"
$ unzip awscli-bundle.zip
$ sudo ./awscli-bundle/install -i /usr/local/aws -b /usr/local/bin/aws
```

3. Configure AWS CLI Profile
```bash
$ aws configure --profile profile_name
```

## Usage

Copy all files in this directory to the root of your Create React App app. Then open `deploy.sh` and replace the following variables at the top:

<table>
  <tr>
    <td><strong>Variable name</strong></td>
    <td><strong>Requirement</strong></td>
    <td><strong>Description</strong></td>
  </tr>

  <tr>
    <td>AWS_PROFILE</td>
    <td>Required</td>
    <td>The name of the profile you used in <code>aws configure --profile profile_name</code></td>
  </tr>

  <tr>
    <td>BUCKET</td>
    <td>Required</td>
    <td>The S3 bucket you'd like to use for this deployment. If it doesn't exist, the script will create it.</td>
  </tr>

  <tr>
    <td>REGION</td>
    <td>Required</td>
    <td>The AWS region you'd like to use for this deployment. S3 and Cloudfront are global in nature and do not require region specification, but this is used for Lambda and Certificate Manager</td>
  </tr>

  <tr>
    <td>LAMBDA_ROLE</td>
    <td>Required</td>
    <td>The name of the Lambda role used to execute Lambda</td>
  </tr>

  <tr>
    <td>LAMBDA_FUNCTION</td>
    <td>Required</td>
    <td>The name of the Lambda function to invoke for URL modification on each request</td>
  </tr>

  <tr>
    <td>CNAME_ALIAS</td>
    <td>Optional</td>
    <td>The CNAME you'll use for this deployment. This is needed if you are planning to aim a DNS record to the Cloudfront distribution. If you don't specify this, then the distribution will only be accessible via the default <code>cloudfront.net</code> URL.</td>
  </tr>

  <tr>
    <td>SSL_CERT_DOMAIN</td>
    <td>Optional</td>
    <td>The domain for which an SSL certificate will be generated in Certificate Manager. This should either match or encompass the <code>CNAME_ALIAS</code>. I recommend you use the wildcard domain <code>*.domain.com</code> which encompasses all subdomains. If you don't specify this, then no SSL certificate will be generated, which is fine if you leave <code>CNAME_ALIAS</code> blank since <code>cloudfront.net</code> already uses Amazon's default Certificate Manager. But if you specify your own custom domain in <code>CNAME_ALIAS</code>, then you'll want to fill this in.
  </tr>
</table>

Then check these files into your repository. To deploy from the command line, run:
```bash
$ ./deploy.sh
```

## Breakdown of `deploy.sh`

* Builds this React app as static files
* Sync static files to S3
* Set the S3 bucket to serve static website content
  * Set index document to `index.html`
  * To make it play nice with React Router, set the error document to `index.html` as well
* Distribute via Cloudfront CDN, connected to the S3 bucket
  * Connect to the public S3 bucket website
  * Connect an SSL certificate created on [AWS Certificate Manager](https://console.aws.amazon.com/acm/home?region=us-east-1)
  * Redirect HTTP to HTTPS
  * Customize object caching with TTL of 31536000 (for min, max, and default TTL)
  * Compress objects automatically
  * Alternate domain names: `www.domain.com`
  * Default root object: `index.html`
  * To make it play nice with React Router, set the error document to `index.html` as well. Do this by going to the **Error Pages** tab for the distribution and clicking "reate Custom Error Response" for 404 (Not Found) and 403 (Forbidden) errors
    * Error Caching Minimum TTL: `0`
    * Response Page Path: `/index.html`
    * HTTP Response Code: `200 OK`
    * Actual 404 paths should be handled by the catch-all React Router route
* Invalidate Cloudfront CDN distribution upon every new deployment
* Point the `www` CNAME for `domain.com` to the Cloudfront domain name (it will look something like `dxxwhv5tk782l.cloudfront.net`)
