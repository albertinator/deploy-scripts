# SSL Manual Deploy on Kubernetes

If for some reason the automated Cert Manager deployment isn't working, take the following steps to generate an SSL certificate and deploy it as a Kubernetes secret.

1. Go to [SSL For Free](https://www.sslforfree.com) and follow the steps to generate a free SSL certificate from Let's Encrypt. Make sure to retrieve the follow files:
* `certificate.crt`
* `private.key`
* `ca_bundle.crt`

2. Then run the following commands to stitch the `.crt` files together (this has to be done in a very specific way) and create the Kubernetes secret in cluster:
```bash
$ echo "$(tput setaf 2)Applying TLS certificate as secret...$(tput sgr0)"
$ awk 1 certificate.crt ca_bundle.crt > full.crt
$ kubectl create secret generic app-secret \
$   --from-file=tls.crt=full.crt \
$   --from-file=tls.key=private.key \
$   --dry-run -o yaml | kubectl apply -f -
$ rm full.crt
$ kubectl get secrets
```
