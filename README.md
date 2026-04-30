# idm-vault-lab

If you're already using Red Hat IDM to manage your RHEL fleet, every enrolled machine has an IDM-issued certificate. This POC demonstrates using that certificate to authenticate to HashiCorp Vault via the TLS cert auth method — giving you machine identity-based access to secrets without AppRole or any shared credentials.

## Infrastructure & Flow

```
  AWS VPC — demo.lab (Route53 private zone)
  ┌─────────────────────────────────────────────────────────────────┐
  │                                                                 │
  │   ┌──────────────────┐              ┌──────────────────────┐    │
  │   │  idm.demo.lab    │──(2)CA cert──►  vault.demo.lab      │    │
  │   │                  │   trusted    │                      │    │
  │   │  Red Hat IDM     │              │  Vault Enterprise    │    │
  │   │  FreeIPA CA      │              │  cert auth method    │    │
  │   └────────┬─────────┘              │  KMS auto-unseal     │    │
  │            │                        └──────────┬───────────┘    │
  │        (1) issues                              │                │
  │        host cert                    (3) vault login -method=cert│
  │        with OU                      (4) token + policy issued   │
  │            │                                   │                │
  │            ▼                                   │                │
  │   ┌──────────────────┐                         │                │
  │   │  client.demo.lab │◄────────────────────────┘                │
  │   │                  │                                          │
  │   │  RHEL VM         │──(5)──► vault kv get secret/web/...      │
  │   │  IDM enrolled    │         (only what the policy allows)     │
  │   └──────────────────┘                                          │
  │                                                                 │
  └─────────────────────────────────────────────────────────────────┘
```

## Role-Based Policy with IDM Cert Profiles

The baseline demo proves the concept: an IDM-enrolled machine uses its host certificate to authenticate to Vault. The natural next question is how you give different machines different levels of access — without maintaining a list of hostnames in Vault.

### The Problem with Naive Cert Auth

The simplest Vault cert auth configuration trusts any certificate signed by the IDM CA. That means every enrolled machine gets the same policy. In practice you need finer control: a web server should be able to read its API config, but it should never be able to read database credentials.

### The Solution: OU-Based Policy, Enforced by IDM

The Organizational Unit (OU) field in the certificate subject is the right attribute to drive Vault policy. A Vault cert auth role with `allowed_organizational_units = ["web-servers"]` will grant access to any cert carrying that OU — no hostnames to list, no per-machine Vault config. Add a new machine to the right group and it automatically gets the right access.

The key is making the OU trustworthy. Vault trusts the IDM CA, so if a client could self-request any OU it wanted, this would be meaningless. IDM prevents this through **cert profiles** and **CA ACLs**:

```
  IDM Host Groups          CA ACLs              Cert Profiles
  ┌──────────────┐         ┌──────────────────┐  ┌──────────────────────────────┐
  │ web-servers  │────────►│ web-servers-acl  │─►│ webServersCert               │
  │  host1       │         │                  │  │ Subject: CN=<host>,          │
  │  host2       │         │ (only hosts in   │  │          OU=web-servers,      │
  │  ...         │         │  this group may  │  │          O=DEMO.LAB          │
  └──────────────┘         │  use this        │  └──────────────────────────────┘
                           │  profile)        │
  ┌──────────────┐         │                  │  ┌──────────────────────────────┐
  │ db-servers   │────────►│ db-servers-acl   │─►│ dbServersCert                │
  │  host3       │         │                  │  │ Subject: CN=<host>,          │
  │  host4       │         │                  │  │          OU=db-servers,       │
  │  ...         │         │                  │  │          O=DEMO.LAB          │
  └──────────────┘         └──────────────────┘  └──────────────────────────────┘
```

A machine in `web-servers` can only request a cert using `webServersCert`. A machine in `db-servers` can only use `dbServersCert`. This is enforced server-side by the IDM CA — the client has no ability to choose a different profile or request a different OU.

### What the Vault Config Looks Like

Two cert auth roles, each matching on OU. No hostnames anywhere:

```hcl
resource "vault_cert_auth_backend_role" "web_servers" {
  name                         = "web-servers"
  certificate                  = var.idm_ca_cert        # trust the IDM CA
  allowed_organizational_units = ["web-servers"]        # match on OU
  token_policies               = ["web-server-policy"]
}

resource "vault_cert_auth_backend_role" "db_servers" {
  name                         = "db-servers"
  certificate                  = var.idm_ca_cert
  allowed_organizational_units = ["db-servers"]
  token_policies               = ["db-server-policy"]
}
```

Two policies with distinct access scopes:

```hcl
# Web servers can only read web secrets
path "secret/data/web/*" { capabilities = ["read"] }

# DB servers can only read database credentials
path "secret/data/db/*"  { capabilities = ["read"] }
```

### What You See in Practice

When a web server authenticates, its cert subject shows the OU stamped by the IDM profile:

```
subject=CN=client.demo.lab, OU=web-servers, O=DEMO.LAB
```

Vault grants the `web-server-policy` token. The machine can read `secret/web/app-config` and receives a 403 if it attempts `secret/db/credentials`. The demo runs both flows and shows the denial explicitly.

### Scaling to Production

At provisioning time, add the new host to the appropriate IDM host group — `web-servers` or `db-servers`. When the host enrolls and requests its cert, the CA ACL ensures it can only use the correct profile, and the correct OU is stamped automatically. No Vault configuration changes are needed. Vault's `allowed_organizational_units` check works for every future machine in that group without modification.

---

## Prerequisites

- AWS account with EC2 key pair
- Red Hat Developer Portal credentials
- Vault Enterprise license
- Terraform installed locally

## Architecture Notes

- **Vault listener uses TLS** — cert auth requires it. The client certificate is presented during the mutual TLS handshake. Vault uses a self-signed cert; clients use `VAULT_SKIP_VERIFY=true`.
- **AWS KMS auto-unseal** — Vault unseals automatically on start via an IAM instance profile. No manual unseal steps needed.
- **Route53 private hosted zone** (`demo.lab`) — all three VMs resolve each other by hostname within the VPC.
- **IDM cert profiles** — created during IDM bootstrap. Each profile has a hardcoded OU in the subject template. CA ACLs bind profiles to host groups server-side.

## Directory Structure

```
terraform/      — AWS infra (VPC, Route53, EC2 instances, SGs, KMS)
vault-config/   — Vault configuration (cert auth roles, policies, KV secrets)
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

Get the IDM CA cert — the Terraform output gives you the exact command:

```bash
terraform -chdir=terraform output -raw idm_ca_cert_command
# Run the printed command and paste the cert into terraform.auto.tfvars
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
2. Add the host to the `web-servers` and `db-servers` IDM host groups
3. Request two host certificates from IDM, each using a different cert profile (`webServersCert`, `dbServersCert`)
4. Display the cert subjects — the OU stamped by each profile is visible here
5. Authenticate to Vault as the web server identity, read the web secret, then show the 403 when attempting to read the DB secret
6. Authenticate to Vault as the DB server identity and read the DB secret

## Manual Demo Commands

Run these on the client VM after the demo script has issued both certs.

### CLI

```bash
export VAULT_ADDR="https://<vault_public_ip>:8200"
export VAULT_SKIP_VERIFY=true

# Web server identity
vault login \
  -method=cert \
  -ca-cert=/etc/ipa/ca.crt \
  -client-cert=/etc/pki/tls/certs/web-client.crt \
  -client-key=/etc/pki/tls/private/web-client.key \
  name=web-servers

vault kv get secret/web/app-config      # succeeds
vault kv get secret/db/credentials     # 403 — policy does not allow this path

# DB server identity
vault login \
  -method=cert \
  -ca-cert=/etc/ipa/ca.crt \
  -client-cert=/etc/pki/tls/certs/db-client.crt \
  -client-key=/etc/pki/tls/private/db-client.key \
  name=db-servers

vault kv get secret/db/credentials     # succeeds
```

### API

```bash
# Authenticate with the web-servers cert and capture the token
TOKEN=$(curl -sk \
  --request POST \
  --cert /etc/pki/tls/certs/web-client.crt \
  --key /etc/pki/tls/private/web-client.key \
  --data '{"name": "web-servers"}' \
  https://<vault_public_ip>:8200/v1/auth/cert/login \
  | jq -r '.auth.client_token')

# Read the authorized secret
curl -sk \
  -H "X-Vault-Token: $TOKEN" \
  https://<vault_public_ip>:8200/v1/secret/data/web/app-config \
  | jq .data.data
```

## Teardown

```bash
cd terraform && terraform destroy
```
