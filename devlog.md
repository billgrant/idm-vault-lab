# devlog.md

This file documents the build history, decisions made, problems hit, and remaining work. It is intended to give an LLM or human contributor full context on the current state of the project before continuing work.

---

## What Was Built

A working proof of concept demonstrating machine identity-based authentication to HashiCorp Vault Enterprise using Red Hat IDM as the certificate authority. Three RHEL 9 EC2 instances are provisioned in AWS:

- **IDM server** (`idm.demo.lab`) — FreeIPA, acts as the CA for the domain
- **Vault server** (`vault.demo.lab`) — Vault Enterprise with AWS KMS auto-unseal and TLS enabled
- **Client VM** (`client.demo.lab`) — enrolls with IDM, receives a host certificate, uses it to authenticate to Vault and read a secret

The full flow works end to end: cert issued by IDM → `vault login -method=cert` → `vault kv get`.

---

## Architecture Decisions

**Why cert auth over AppRole?**
The whole point of this POC is that if you already use Red Hat IDM to manage your RHEL fleet, every enrolled machine already has an IDM-issued certificate. Cert auth lets you use that existing identity to authenticate to Vault — no shared secrets, no credential distribution problem that AppRole has.

**AWS KMS auto-unseal**
Added early in the build. With KMS configured in `vault.hcl` before `vault operator init` runs, Vault initializes with KMS auto-unseal from the start — no Shamir key ceremony needed. The Vault EC2 instance has an IAM instance profile with `kms:Encrypt`, `kms:Decrypt`, `kms:DescribeKey` on the key.

**Route53 private hosted zone (`demo.lab`)**
IDM requires consistent forward and reverse DNS. A Route53 private hosted zone handles internal name resolution between the three VMs. The IDM server is assigned a fixed private IP (`10.0.1.10`) so the DNS record is stable before the instance is fully bootstrapped.

**Vault TLS**
Vault's listener must have TLS enabled for cert auth to work — the client certificate is presented during the mutual TLS handshake. Vault uses a self-signed cert generated at bootstrap time. Clients use `VAULT_SKIP_VERIFY=true`. This is acceptable for a POC; a production deployment would use a cert from IDM for Vault itself.

---

## Problems Encountered

### 1. IDM hostname mismatch
`ipa-server-install` failed because the EC2 instance hostname (`ip-10-0-1-10.ec2.internal`) didn't match the desired hostname (`idm.demo.lab`). Setting the hostname with `hostnamectl` alone wasn't sufficient — IPA also checks `/etc/hosts`.

**Fix:** Added `echo "10.0.1.10 idm.demo.lab idm" >> /etc/hosts` to `userdata/idm-server.sh` before the `ipa-server-install` call.

### 2. Cert auth returning 400 over HTTP
`vault login -method=cert` returned a 400 with no error detail when `VAULT_ADDR` was `http://`. The client cert is presented during the TLS handshake — there is no handshake over plain HTTP, so Vault never sees the cert.

**Fix:** Enabled TLS on the Vault listener using a self-signed cert generated in userdata. Updated all references to use `https://` and `VAULT_SKIP_VERIFY=true`.

### 3. Permission denied reading client cert
After `ipa-getcert` issued the cert, the files were owned by root. Running vault commands as `ec2-user` failed with `permission denied`.

**Fix:** Added `chown ec2-user` and `chmod` calls in `demo.sh` immediately after cert issuance.

### 4. API cert login requires POST body with role name
The initial API example used `curl` without a request body. Vault's `/v1/auth/cert/login` endpoint requires the role name as a JSON POST body (`{"name": "idm-clients"}`), otherwise it returns an error.

**Fix:** Updated README API example to use `--request POST --data '{"name": "idm-clients"}'`.

---

## Current State

The POC is fully functional. Both the CLI and API demo flows work from the client VM:

- `vault login -method=cert` with the IDM-issued host cert authenticates successfully
- `vault kv get secret/demo/machine-secret` returns the demo secret
- The API flow (curl → token → curl for secret) also works

All infrastructure is Terraform-managed and can be rebuilt cleanly with `terraform apply`.

---

## What Still Needs to Be Done (to make it demo-ready)

The POC proves the concept but needs polish before it can be shown to a customer or used in a demo. Key areas:

1. **Demo script UX** — `demo.sh` is functional but outputs a lot of noise. Consider a cleaner version that prints only the key steps and outputs with clear section headers, suitable for a screen share.

2. **Vault UI walkthrough** — The Vault UI is enabled but not part of the demo flow. Walking through the cert auth method configuration, the policy, and the entity that gets created after login would make the demo more visual and easier to follow.

3. **Entity visibility** — After a successful cert login, Vault creates an entity. Showing this in the UI (`Access → Entities`) reinforces the machine identity story. The demo should include a `vault token lookup` or UI step to show what identity Vault assigned to the machine.

4. **Vault cert for Vault itself** — Currently Vault uses a self-signed cert and clients use `VAULT_SKIP_VERIFY=true`. For a cleaner demo, Vault should use a cert issued by IDM. This requires a chicken-and-egg bootstrap (IDM must be up before Vault gets its cert), likely solved by a post-init configuration step or a second Terraform apply.

5. **Demo secret content** — The current secret (`api_key`, `environment`) is placeholder. Replace with something that tells a story — e.g., a database password or API credential that a "real" RHEL service would consume.

6. **Rebuild automation** — Currently requires ~6 manual steps across two terminals. A single `make demo` or wrapper script that handles the full sequence (apply infra → wait for IDM → apply vault-config → SCP demo.sh → SSH to client) would make repeated demos less error-prone.

7. **Teardown reminder** — The three EC2 instances + KMS key cost money while running. A note or script to remind/automate teardown after a demo session would be useful.
