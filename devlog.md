# devlog.md

This file documents the build history, decisions made, problems hit, and current state. It is intended to give an LLM or human contributor full context before continuing work.

---

## What Was Built

A working proof of concept demonstrating role-based machine identity authentication to HashiCorp Vault Enterprise using Red Hat IDM as the certificate authority. Three RHEL 9 EC2 instances on AWS:

- **IDM server** (`idm.demo.lab`) — FreeIPA CA, custom cert profiles, host groups, CA ACLs
- **Vault server** (`vault.demo.lab`) — Vault Enterprise with AWS KMS auto-unseal and TLS
- **Client VM** (`client.demo.lab`) — enrolls with IDM, receives role-stamped host certs, authenticates to Vault with least-privilege access

The full flow works end to end:
- IDM host group membership → CA ACL → cert profile → OU stamped in cert → Vault cert auth role matches OU → scoped policy
- Web identity: reads `secret/web/app-config`, denied on `secret/db/credentials`
- DB identity: reads `secret/db/credentials`, denied on `secret/web/app-config`

---

## Architecture Decisions

**Why cert auth over AppRole?**
Every IDM-enrolled RHEL machine already has an IDM-issued certificate. Cert auth uses that existing identity — no shared secrets, no credential distribution problem.

**Why OU over DNS SANs for policy differentiation?**
`allowed_dns_sans` requires every machine's hostname to follow a naming convention, which ties security policy to DNS naming. OU is group-based: add a machine to an IDM host group and it automatically gets the right policy, regardless of its hostname. This scales correctly in production.

**Why IDM cert profiles + CA ACLs over manually specifying the subject?**
Dogtag (IDM's underlying CA) applies its profile server-side and rewrites the cert subject regardless of what the client requests. The `-N` flag in `ipa-getcert` and service principal names both failed to produce a different CN or OU — the profile always won. The correct approach is custom profiles with the OU hardcoded in the subject template, access-controlled by CA ACLs bound to host groups.

**AWS KMS auto-unseal**
Configured in `vault.hcl` before `vault operator init`, so Vault initializes with KMS unseal from the start. The Vault EC2 instance has an IAM instance profile with the required KMS permissions.

**Route53 private hosted zone (`demo.lab`)**
IDM requires consistent forward DNS. The IDM server has a fixed private IP (`10.0.1.10`) so the DNS record is stable before the instance fully bootstraps.

**Vault TLS**
Cert auth requires TLS — the client cert is presented during the mutual TLS handshake. Vault uses a self-signed cert generated at bootstrap. Clients use `VAULT_SKIP_VERIFY=true`. Acceptable for a POC.

---

## Problems Encountered

### 1. IDM hostname mismatch
`ipa-server-install` failed because the EC2 hostname (`ip-10-0-1-10.ec2.internal`) didn't match `idm.demo.lab`. IPA checks both `hostnamectl` and `/etc/hosts`.

**Fix:** Added `echo "10.0.1.10 idm.demo.lab idm" >> /etc/hosts` before `ipa-server-install`.

### 2. Cert auth returning 400 over HTTP
`vault login -method=cert` returned a 400 when `VAULT_ADDR` was `http://`. The client cert is presented during the TLS handshake — there is no handshake over plain HTTP.

**Fix:** Enabled TLS on the Vault listener. Updated all references to `https://` with `VAULT_SKIP_VERIFY=true`.

### 3. Permission denied reading client cert
After `ipa-getcert` issued the cert, files were owned by root. Vault commands run as `ec2-user` failed.

**Fix:** Added `chown ec2-user` and `chmod` calls in `demo.sh` after cert issuance.

### 4. API cert login requires POST body with role name
`vault login` via API without a request body returns an error. The role name must be a JSON POST body.

**Fix:** Updated to `--request POST --data '{"name": "web-servers"}'`.

### 5. IDM profile rewrites cert subject — `-N` flag ignored
Attempted to use `ipa-getcert request -N "CN=...,OU=web-servers,O=DEMO.LAB"` to set the OU. The cert was issued with `CN=client.demo.lab, O=DEMO.LAB` — no OU. Dogtag's profile applies server-side and rewrites the subject regardless of the CSR.

**Fix:** Created custom cert profiles (`webServersCert`, `dbServersCert`) with the OU hardcoded in the subject template. CA ACLs bind host groups to profiles.

### 6. Service principal CN not what was expected
Attempted `ipa service-add web/client.demo.lab` and requested a cert with `-K web/client.demo.lab`, expecting `CN=web/client.demo.lab`. The cert came out `CN=client.demo.lab` — IDM's profile extracts only the hostname portion of the principal.

**Fix:** Same as above — custom cert profiles are the correct solution.

### 7. `ipa certprofile-import` profile ID mismatch
`ipa certprofile-import webServersCert` failed with "Profile ID 'webServersCert' does not match profile data 'caIPAserviceCert'". The exported `.cfg` file contains `profileId=caIPAserviceCert` and the import validates that it matches the command-line argument.

**Fix:** Added `-e 's/^profileId=.*/profileId=webServersCert/'` to the sed command that transforms the base profile before import.

---

## Current State

Fully functional. The demo runs cleanly from `terraform apply` through `demo.sh` without manual intervention:

- IDM bootstrap creates cert profiles, host groups, and CA ACLs automatically
- `demo.sh` enrolls, assigns host to both groups, requests two role-stamped certs, runs four Vault interactions
- Both cert subjects show the expected OU (`OU=web-servers`, `OU=db-servers`)
- Vault policy enforcement works: correct access granted, cross-role access denied with 403

All infrastructure is Terraform-managed and rebuilds cleanly with `terraform destroy && terraform apply`.

---

## Deployment Workflow

```
cd terraform && terraform apply
# Watch IDM bootstrap: terraform output -raw idm_bootstrap_log
# Wait for idm-ready sentinel

cd ../vault-config
# Fill in terraform.auto.tfvars:
#   vault_addr  = terraform output -raw vault_addr  (from terraform/)
#   vault_token = from vault-init.json on Vault server
#   idm_ca_cert = terraform output -raw idm_ca_cert_command | bash
VAULT_SKIP_VERIFY=true terraform apply

# Copy and run demo
terraform -chdir=terraform output -raw scp_demo_sh | bash
ssh <client> 'sudo bash ~/demo.sh <vault_ip> <idm_admin_password>'
```

---

## What Could Still Be Done

1. **Vault cert for Vault itself** — Vault currently uses a self-signed cert. A cleaner demo would use an IDM-issued cert for the Vault listener, removing the need for `VAULT_SKIP_VERIFY=true`. Requires a post-init step after IDM is up.

2. **Entity visibility in Vault UI** — After a successful cert login, Vault creates an entity. Walking through `Access → Entities` in the UI reinforces the machine identity story and would be a strong addition to a live demo.

3. **Single `make demo` wrapper** — The deployment still requires several manual steps across two directories. A `Makefile` that handles the full sequence (apply infra → wait for IDM → apply vault-config → SCP demo.sh → run) would reduce friction for repeated demos.

4. **Teardown reminder** — Three EC2 instances + KMS key cost money while running. A `make teardown` target or similar would help.
