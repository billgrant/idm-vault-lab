#!/bin/bash
# demo.sh — Run on the client VM after IDM enrollment and vault-config is applied.
# Usage: sudo bash demo.sh <vault_public_ip> <idm_admin_password>
set -euo pipefail

VAULT_IP="${1:?Usage: sudo bash demo.sh <vault_public_ip> <idm_admin_password>}"
IDM_ADMIN_PASS="${2:?Usage: sudo bash demo.sh <vault_public_ip> <idm_admin_password>}"

export VAULT_ADDR="https://${VAULT_IP}:8200"
export VAULT_SKIP_VERIFY=true   # Vault uses a self-signed cert

echo ""
echo "======================================================="
echo " IDM → Vault TLS Auth Demo: OU-Based Least Privilege"
echo "======================================================="
echo " Vault: $VAULT_ADDR"
echo ""

# ── Reset from previous run ───────────────────────────────────────────────────
# Kinit and group removal must happen BEFORE ipa-client-install --uninstall,
# which tears down the local Kerberos config.
if [ -f /etc/ipa/default.conf ]; then
  echo "--- Previous enrollment detected, resetting for clean demo ---"
  ipa-getcert stop-tracking -f /etc/pki/tls/certs/web-client.crt &>/dev/null || true
  ipa-getcert stop-tracking -f /etc/pki/tls/certs/db-client.crt  &>/dev/null || true
  echo "${IDM_ADMIN_PASS}" | kinit admin
  ipa hostgroup-remove-member web-servers --hosts=client.demo.lab &>/dev/null || true
  ipa hostgroup-remove-member db-servers  --hosts=client.demo.lab &>/dev/null || true
  kdestroy
  ipa-client-install --uninstall --unattended
  rm -f /etc/pki/tls/certs/web-client.crt /etc/pki/tls/private/web-client.key
  rm -f /etc/pki/tls/certs/db-client.crt  /etc/pki/tls/private/db-client.key
  echo "--- Reset complete ---"
fi

# ── Step 1: Unseal check ──────────────────────────────────────────────────────
echo "--- Checking Vault status ---"
vault status

# ── Step 2: Enroll with IDM ───────────────────────────────────────────────────
echo ""
echo "=== Step 1: Enroll client with Red Hat IDM ==="
ipa-client-install \
  --unattended \
  --domain=demo.lab \
  --server=idm.demo.lab \
  --principal=admin \
  --password="${IDM_ADMIN_PASS}" \
  --mkhomedir

# ── Step 3: Assign host to both groups and request two certs ──────────────────
# In production each machine is in exactly ONE group and can only use that
# group's cert profile (enforced by CA ACL). Here we add the demo VM to both
# groups so we can demonstrate both identities from a single machine.
echo ""
echo "=== Step 2: Assign host to IDM groups and request role-stamped certs ==="
mkdir -p /etc/pki/tls/certs /etc/pki/tls/private

echo "${IDM_ADMIN_PASS}" | kinit admin
ipa hostgroup-add-member web-servers --hosts=client.demo.lab
ipa hostgroup-add-member db-servers  --hosts=client.demo.lab
kdestroy

echo "--- Requesting web-servers cert (profile stamps OU=web-servers) ---"
ipa-getcert request \
  -f /etc/pki/tls/certs/web-client.crt \
  -k /etc/pki/tls/private/web-client.key \
  -K host/client.demo.lab \
  -T webServersCert \
  -w

echo "--- Requesting db-servers cert (profile stamps OU=db-servers) ---"
ipa-getcert request \
  -f /etc/pki/tls/certs/db-client.crt \
  -k /etc/pki/tls/private/db-client.key \
  -K host/client.demo.lab \
  -T dbServersCert \
  -w

echo ""
echo "--- Cert subjects (OU is stamped by the IDM cert profile) ---"
echo "Web cert:"; openssl x509 -in /etc/pki/tls/certs/web-client.crt -noout -subject
echo "DB cert: "; openssl x509 -in /etc/pki/tls/certs/db-client.crt  -noout -subject

chown ec2-user:ec2-user \
  /etc/pki/tls/certs/web-client.crt /etc/pki/tls/private/web-client.key \
  /etc/pki/tls/certs/db-client.crt  /etc/pki/tls/private/db-client.key
chmod 644 /etc/pki/tls/certs/web-client.crt /etc/pki/tls/certs/db-client.crt
chmod 640 /etc/pki/tls/private/web-client.key /etc/pki/tls/private/db-client.key

# ── Step 4: Demo — OU in cert drives Vault policy ────────────────────────────
echo ""
echo "=== [1/4] Web server (OU=web-servers) authenticates to Vault ==="
vault login \
  -method=cert \
  -ca-cert=/etc/ipa/ca.crt \
  -client-cert=/etc/pki/tls/certs/web-client.crt \
  -client-key=/etc/pki/tls/private/web-client.key \
  name=web-servers

echo ""
echo "=== [2/4] Web server reads its authorized secret ==="
vault kv get secret/web/app-config

echo ""
echo "=== [3/4] Web server DENIED: attempts to read DB credentials ==="
vault kv get secret/db/credentials || echo "^^^ Access denied — least privilege enforced ^^^"

echo ""
echo "=== [4/4] DB server (OU=db-servers) authenticates and reads its authorized secret ==="
vault login \
  -method=cert \
  -ca-cert=/etc/ipa/ca.crt \
  -client-cert=/etc/pki/tls/certs/db-client.crt \
  -client-key=/etc/pki/tls/private/db-client.key \
  name=db-servers

vault kv get secret/db/credentials

echo ""
echo "=== Demo complete ==="
echo ""
echo "Key takeaway: Vault policy is driven by OU in the cert subject."
echo "The OU is stamped by the IDM cert profile — not by the client."
echo "CA ACLs enforce which host groups can use which profile, so no"
echo "machine can self-issue a different OU to escalate its access."
echo ""
echo "In production: add a host to the web-servers or db-servers IDM"
echo "host group at provisioning time. The right OU appears in its cert"
echo "automatically. No per-hostname config in Vault is ever needed."
