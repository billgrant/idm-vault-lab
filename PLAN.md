# Plan: idm-vault-lab POC

## Status: Complete

Both phases are implemented and verified end-to-end.

---

## Phase 1 — Machine Identity (Complete)

Red Hat IDM as CA → RHEL client enrolls → IDM-issued host cert → Vault cert auth → secret read.

All infrastructure Terraform-managed on AWS. Three RHEL 9 EC2 instances:
- `idm.demo.lab` — FreeIPA CA
- `vault.demo.lab` — Vault Enterprise, KMS auto-unseal, TLS enabled
- `client.demo.lab` — enrolls with IDM, requests cert, authenticates to Vault

## Phase 2 — Role-Based Least Privilege (Complete)

OU-based policy differentiation using IDM cert profiles and CA ACLs. No per-hostname Vault configuration.

### How It Works

1. IDM bootstrap creates two custom cert profiles derived from `caIPAserviceCert`:
   - `webServersCert` — stamps `OU=web-servers` in the cert subject
   - `dbServersCert` — stamps `OU=db-servers` in the cert subject

2. Two IDM host groups (`web-servers`, `db-servers`) are created with CA ACLs binding each group to exactly one profile. A host in `web-servers` cannot request a `dbServersCert` — enforced server-side by Dogtag.

3. Vault cert auth roles match on `allowed_organizational_units`:
   - `web-servers` role → `web-server-policy` → reads `secret/data/web/*`
   - `db-servers` role → `db-server-policy` → reads `secret/data/db/*`

4. Demo script adds the client to both groups (demo shortcut), requests both certs using `-T <profile>`, and runs four Vault interactions: web login → read web secret → denied on db secret → db login → read db secret.

### Production Path

At provisioning time, add a host to the appropriate IDM host group. When the machine enrolls and requests its cert, the CA ACL ensures it can only use the correct profile, and the OU is stamped automatically. No Vault changes needed for new machines.

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
│       ├── idm-server.sh   # IPA install + cert profiles + host groups + CA ACLs
│       ├── vault-server.sh # Vault install + KMS unseal + TLS + init
│       └── client.sh       # IPA client + Vault CLI install
├── vault-config/           # Vault Terraform config
│   ├── main.tf             # cert auth roles, policies, KV secrets
│   ├── variables.tf
│   └── providers.tf
├── scripts/
│   └── demo.sh             # Full demo — enrollment, cert request, Vault auth, least-privilege proof
├── CLAUDE.md
├── README.md
├── PLAN.md
└── devlog.md
```

---

## Configuration Values

| Variable | Value |
|----------|-------|
| AWS region | `us-east-1` |
| EC2 key pair | `billgrant` |
| IDM realm | `DEMO.LAB` |
| IDM domain | `demo.lab` |
| IDM server private IP | `10.0.1.10` (fixed, required for DNS stability) |
| RH subscription credentials | Terraform variable — never hardcoded |
| Vault Enterprise license | Terraform variable — never hardcoded |
| IDM admin/DS passwords | Terraform variable — never hardcoded |
