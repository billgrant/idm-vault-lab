# Plan: idm-vault-lab POC

## Context
Build a proof of concept in the empty `idm-vault-lab/` repo demonstrating machine identity:
- Red Hat IDM (FreeIPA) acts as the CA for a RHEL client VM
- The client VM authenticates to Vault Enterprise using the TLS/cert auth method with its IDM-issued cert
- The client reads a secret from Vault

All infrastructure runs on AWS (sandbox account). Vault Enterprise license available. Red Hat Developer Portal access available.

---

## Directory Structure

```
idm-vault-lab/
├── terraform/              # AWS infrastructure
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── providers.tf
│   └── userdata/
│       ├── idm-server.sh
│       ├── vault-server.sh
│       └── client.sh
├── vault-config/           # Vault TLS auth configuration
│   ├── main.tf
│   ├── variables.tf
│   └── providers.tf
├── scripts/
│   └── demo.sh             # Runs on the client VM
└── README.md
```

---

## Step 1 — Terraform Infrastructure (`terraform/`)

### Resources
- **VPC** with a single public subnet (simple for a POC)
- **Route53 private hosted zone**: `demo.lab`
  - `idm.demo.lab` → IDM server
  - `vault.demo.lab` → Vault server
  - `client.demo.lab` → client VM
- **Security groups**:
  - IDM SG: inbound 22 (SSH), 80, 443, 389, 636, 88 (TCP/UDP), 464, 123 (NTP)
  - Vault SG: inbound 22, 8200
  - Client SG: inbound 22
  - All three: allow all traffic within the VPC
- **Key pair**: variable pointing to user's existing key pair name
- **EC2 instances**:
  - IDM server: RHEL 9 AMI, `t3.medium` (IDM needs headroom), userdata = `idm-server.sh`
  - Vault server: RHEL 9 AMI, `t3.small`, userdata = `vault-server.sh`
  - Client VM: RHEL 9 AMI, `t3.small`, userdata = `client.sh`
- **RHEL 9 AMI**: use `data "aws_ami"` filter on `RHEL-9*` owner `309956199498` (Red Hat's official AWS account)

### Outputs
- Public IPs of all three instances
- SSH commands to connect to each
- Route53 zone ID (needed for vault-config step)

---

## Step 2 — Userdata Bootstrap Scripts

### `userdata/idm-server.sh`
```bash
#!/bin/bash
# Register with Red Hat (developer subscription)
subscription-manager register --username=<var> --password=<var> --auto-attach

# Install IDM server packages
dnf install -y ipa-server ipa-server-dns

# Unattended install
ipa-server-install \
  --unattended \
  --realm=DEMO.LAB \
  --domain=demo.lab \
  --hostname=idm.demo.lab \
  --ds-password=<var> \
  --admin-password=<var> \
  --no-ntp

# Export CA cert to accessible location
cp /etc/ipa/ca.crt /home/ec2-user/idm-ca.crt
chmod 644 /home/ec2-user/idm-ca.crt
```

### `userdata/vault-server.sh`
```bash
#!/bin/bash
# Install Vault Enterprise
yum install -y yum-utils
yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
yum install -y vault-enterprise

# Write license
echo "<vault_license>" > /etc/vault.d/vault.hclic

# vault.hcl — no TLS needed on Vault listener for cert auth to work
cat > /etc/vault.d/vault.hcl <<EOF
ui = true
storage "file" { path = "/opt/vault/data" }
listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = true
}
license_path = "/etc/vault.d/vault.hclic"
EOF

systemctl enable vault
systemctl start vault

# Initialize and store credentials (POC only)
sleep 5
vault operator init -format=json > /home/ec2-user/vault-init.json
chmod 600 /home/ec2-user/vault-init.json
```

### `userdata/client.sh`
```bash
#!/bin/bash
# Install IPA client packages — enrollment happens later in demo.sh
dnf install -y ipa-client
```

---

## Step 3 — Vault Configuration Terraform (`vault-config/`)

Run after IDM is up and the IDM CA cert has been copied off the IDM server.

### `variables.tf`
- `vault_addr` — Vault server address (from terraform output)
- `vault_token` — root token from vault-init.json
- `idm_ca_cert` — contents of `idm-ca.crt` (read with `file()`)

### `main.tf` resources
```hcl
# KV v2 secrets engine
resource "vault_mount" "secret" {
  path = "secret"
  type = "kv-v2"
}

# Demo secret
resource "vault_kv_secret_v2" "demo" {
  mount     = vault_mount.secret.path
  name      = "demo/machine-secret"
  data_json = jsonencode({ api_key = "abc123", environment = "production" })
}

# Policy
resource "vault_policy" "idm_client" {
  name   = "idm-client-policy"
  policy = <<EOT
path "secret/data/demo/*" { capabilities = ["read"] }
EOT
}

# Enable cert auth
resource "vault_auth_backend" "cert" {
  type = "cert"
}

# Trust IDM CA — any cert signed by IDM CA gets the policy
resource "vault_cert_auth_backend_role" "idm_clients" {
  name           = "idm-clients"
  certificate    = var.idm_ca_cert
  backend        = vault_auth_backend.cert.path
  token_policies = [vault_policy.idm_client.name]
}
```

---

## Step 4 — Demo Script (`scripts/demo.sh`)

Runs on the **client VM**. Requires IDM and Vault to be up and vault-config applied.

```bash
#!/bin/bash
set -e

VAULT_ADDR="http://vault.demo.lab:8200"
export VAULT_ADDR

echo "=== Step 1: Enroll with IDM ==="
ipa-client-install \
  --unattended \
  --domain=demo.lab \
  --server=idm.demo.lab \
  --principal=admin \
  --password=<admin_password>

echo "=== Step 2: Request cert from IDM CA ==="
ipa-getcert request \
  -f /etc/pki/tls/certs/client.crt \
  -k /etc/pki/tls/private/client.key \
  -K host/client.demo.lab

# Wait for cert issuance
sleep 10

echo "=== Step 3: Authenticate to Vault with cert ==="
vault login \
  -method=cert \
  -ca-cert=/etc/ipa/ca.crt \
  -client-cert=/etc/pki/tls/certs/client.crt \
  -client-key=/etc/pki/tls/private/client.key \
  name=idm-clients

echo "=== Step 4: Read secret from Vault ==="
vault kv get secret/demo/machine-secret
```

---

## Deployment Order

1. `cd terraform && terraform apply` — creates VPC, DNS, EC2 instances (IDM bootstrap takes ~10-15 min)
2. SSH to IDM server, `cat ~/idm-ca.crt` — copy the CA cert
3. `cd vault-config && terraform apply -var="idm_ca_cert=$(cat idm-ca.crt)" ...` — configure Vault
4. SSH to client VM, run `sudo bash demo.sh`

---

## Files to Create

- `idm-vault-lab/terraform/main.tf`
- `idm-vault-lab/terraform/variables.tf`
- `idm-vault-lab/terraform/outputs.tf`
- `idm-vault-lab/terraform/providers.tf`
- `idm-vault-lab/terraform/userdata/idm-server.sh`
- `idm-vault-lab/terraform/userdata/vault-server.sh`
- `idm-vault-lab/terraform/userdata/client.sh`
- `idm-vault-lab/vault-config/main.tf`
- `idm-vault-lab/vault-config/variables.tf`
- `idm-vault-lab/vault-config/providers.tf`
- `idm-vault-lab/scripts/demo.sh`
- `idm-vault-lab/README.md`

---

## Configuration Values

| Variable | Value |
|----------|-------|
| AWS region | `us-east-1` |
| EC2 key pair | `billgrant` |
| RH subscription username | Terraform variable — passed at apply time, never hardcoded |
| RH subscription password | Terraform variable — passed at apply time, never hardcoded |
| Vault Enterprise license | Terraform variable — passed at apply time, never hardcoded |
| IDM admin password | Terraform variable — passed at apply time, never hardcoded |
| IDM DS (directory) password | Terraform variable — passed at apply time, never hardcoded |

## Notes
- RHEL 9 AMI is looked up dynamically via `data "aws_ami"` (owner `309956199498` = Red Hat official)
- Plan file will be moved to `idm-vault-lab/PLAN.md` at start of implementation
