# idm-vault-lab

If you're already using Red Hat IDM to manage your RHEL fleet, every enrolled machine has an IDM-issued certificate. This POC demonstrates using that certificate to authenticate to HashiCorp Vault via the TLS cert auth method — giving you machine identity-based access to secrets without AppRole or any shared credentials.

## Flow

```
Red Hat IDM (CA)
  └─ issues host cert to client VM
       └─ client presents cert to Vault via mutual TLS
            └─ Vault validates cert against IDM CA → issues token
                 └─ client reads secret/demo/machine-secret
```

## Prerequisites

- AWS sandbox account with EC2 key pair named `billgrant`
- Red Hat Developer Portal credentials
- Vault Enterprise license
- Terraform installed locally

## Architecture Notes

- **Vault listener uses TLS** — cert auth requires it. The client certificate is presented during the mutual TLS handshake. Vault uses a self-signed cert; clients use `VAULT_SKIP_VERIFY=true`.
- **AWS KMS auto-unseal** — Vault unseals automatically on start via an IAM instance profile. No manual unseal steps needed.
- **Route53 private hosted zone** (`demo.lab`) — all three VMs resolve each other by hostname within the VPC.

## Directory Structure

```
terraform/      — AWS infra (VPC, Route53, EC2 instances, SGs, KMS)
vault-config/   — Vault configuration (cert auth, policy, KV secret)
scripts/        — demo.sh runs on the client VM
```

## Deployment

### 1. Provision infrastructure

Copy the example tfvars and fill in your values:
```bash
cd terraform
cp terraform.auto.tfvars.example terraform.auto.tfvars
# edit terraform.auto.tfvars
terraform init
terraform apply
```

IDM takes **15–20 minutes** to fully bootstrap. Monitor progress:
```bash
ssh -i ~/.ssh/<key_pair_name>.pem ec2-user@<idm_public_ip> 'tail -f /var/log/idm-bootstrap.log'
# Done when you see: /home/ec2-user/idm-ready
```

Vault bootstraps faster (~2 min). Confirm it's ready:
```bash
ssh -i ~/.ssh/<key_pair_name>.pem ec2-user@<vault_public_ip> 'cat ~/vault-ready'
```

### 2. Save Vault credentials

Vault auto-unseals via KMS. Just save the root token and recovery keys:
```bash
ssh -i ~/.ssh/<key_pair_name>.pem ec2-user@<vault_public_ip> 'cat ~/vault-init.json'
```

### 3. Configure Vault

Copy the example tfvars and fill in your values:
```bash
cd vault-config
cp terraform.auto.tfvars.example terraform.auto.tfvars
# edit terraform.auto.tfvars:
#   vault_addr  = "https://<vault_public_ip>:8200"   ← must be https
#   vault_token = <root_token from vault-init.json>
#   idm_ca_cert = <contents of ~/idm-ca.crt from IDM server>
```

Get the IDM CA cert:
```bash
ssh -i ~/.ssh/<key_pair_name>.pem ec2-user@<idm_public_ip> 'cat ~/idm-ca.crt'
```

Apply — `VAULT_SKIP_VERIFY=true` is required because Vault uses a self-signed cert:
```bash
VAULT_SKIP_VERIFY=true terraform init
VAULT_SKIP_VERIFY=true terraform apply
```

### 4. Run the demo

Copy `demo.sh` to the client VM and run it:
```bash
scp -i ~/.ssh/<key_pair_name>.pem scripts/demo.sh ec2-user@<client_public_ip>:~/
ssh -i ~/.ssh/<key_pair_name>.pem ec2-user@<client_public_ip>
sudo bash demo.sh <vault_public_ip> <idm_admin_password>
```

The script will:
1. Enroll the client with IDM (`ipa-client-install`)
2. Request a host certificate from the IDM CA (`ipa-getcert`)
3. Authenticate to Vault using the cert (`vault login -method=cert`)
4. Read a secret from Vault (`vault kv get secret/demo/machine-secret`)

## Manual / Demo Commands

Run these on the client VM after IDM enrollment and vault-config are applied. Both assume the host cert has already been issued by IDM.

### CLI

```bash
export VAULT_ADDR="https://<vault_public_ip>:8200"
export VAULT_SKIP_VERIFY=true

vault login \
  -method=cert \
  -client-cert=/etc/pki/tls/certs/client.crt \
  -client-key=/etc/pki/tls/private/client.key \
  name=idm-clients

vault kv get secret/demo/machine-secret
```

### API

```bash
# Step 1: Authenticate with the IDM-issued cert and capture the token
# The role name must be passed as a JSON body
TOKEN=$(curl -sk \
  --request POST \
  --cert /etc/pki/tls/certs/client.crt \
  --key /etc/pki/tls/private/client.key \
  --data '{"name": "idm-clients"}' \
  https://<vault_public_ip>:8200/v1/auth/cert/login \
  | jq -r '.auth.client_token')

# Step 2: Read the secret
curl -sk \
  -H "X-Vault-Token: $TOKEN" \
  https://<vault_public_ip>:8200/v1/secret/data/demo/machine-secret \
  | jq .data.data
```

## Teardown

```bash
cd terraform && terraform destroy
```
