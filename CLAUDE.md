# CLAUDE.md — idm-vault-lab

## What This Is

A customer-facing demo lab proving machine identity-based authentication to HashiCorp Vault Enterprise using Red Hat IDM (FreeIPA) as the CA. It demonstrates role-based least privilege: different machine tiers get different Vault policies automatically, driven by OU in the cert subject — no per-hostname Vault configuration.

This repo is shared directly with customers. It must work end-to-end from a clean `terraform apply`. Read `devlog.md` for full context on decisions and problems encountered.

## Critical Rule

**Never suggest manual fixes on running infrastructure.** If something is broken, fix the source file (userdata script, Terraform config, demo.sh) and rebuild with `terraform destroy && terraform apply`. The lab must work for a customer running it cold with no tribal knowledge.

## Deployment Workflow

```
# 1. Infrastructure
cd terraform && terraform apply
# Watch IDM bootstrap (~15 min): terraform output -raw idm_bootstrap_log
# Wait for idm-ready

# 2. Vault config — VAULT_SKIP_VERIFY=true is required (Vault uses self-signed cert)
cd ../vault-config
# Populate terraform.auto.tfvars:
#   vault_addr  — from: terraform -chdir=../terraform output -raw vault_addr
#   vault_token — from vault-init.json on the Vault server
#   idm_ca_cert — run the command from: terraform -chdir=../terraform output -raw idm_ca_cert_command
VAULT_SKIP_VERIFY=true terraform apply

# 3. Run the demo
terraform -chdir=terraform output -raw scp_demo_sh | bash
ssh <client> 'sudo bash ~/demo.sh <vault_public_ip> <idm_admin_password>'

# Teardown
cd terraform && terraform destroy
```

## How the Policy Works

IDM bootstrap (`terraform/userdata/idm-server.sh`) creates:
- Two cert profiles: `webServersCert` (stamps `OU=web-servers`) and `dbServersCert` (stamps `OU=db-servers`)
- Two host groups: `web-servers`, `db-servers`
- CA ACLs binding each host group to exactly one profile — server-side enforcement by Dogtag

Vault cert auth roles match on `allowed_organizational_units`. No hostnames in Vault config.

In production: add a host to the right IDM host group at provisioning time. The OU appears in its cert automatically. Vault policy follows with no further configuration.

## Key Files

| File | Purpose |
|------|---------|
| `terraform/userdata/idm-server.sh` | IPA install + cert profiles + host groups + CA ACLs |
| `terraform/userdata/vault-server.sh` | Vault install, KMS unseal config, TLS cert, init |
| `terraform/userdata/client.sh` | IPA client + Vault CLI install |
| `terraform/outputs.tf` | All SSH/SCP commands pre-populated with IPs |
| `vault-config/main.tf` | Cert auth roles, policies, KV secrets |
| `scripts/demo.sh` | Full demo script — idempotent, safe to re-run |

## Sensitive Variables (never hardcode)

- `rh_username` / `rh_password` — Red Hat subscription
- `vault_license` — Vault Enterprise license
- `idm_admin_password` / `idm_ds_password` — IDM passwords
- `vault_token` — Vault root token (vault-config only)

All live in `terraform.auto.tfvars` and `vault-config/terraform.auto.tfvars`, both gitignored.

## Known Limitations

- Vault uses a self-signed cert (`VAULT_SKIP_VERIFY=true`). A proper deployment would use an IDM-issued cert for Vault.
- The demo adds the client VM to both host groups (web-servers and db-servers) to simulate two machine types from one VM. In production each machine is in exactly one group.
