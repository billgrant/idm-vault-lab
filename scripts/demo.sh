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
echo " IDM → Vault TLS Auth Demo"
echo "======================================================="
echo " Vault: $VAULT_ADDR"
echo ""

# ── Reset from previous run ───────────────────────────────────────────────────
# Makes the script safe to run repeatedly — unenroll and clean up cert state
# before starting fresh. No-ops on a clean machine.
if [ -f /etc/ipa/default.conf ]; then
  echo "--- Previous enrollment detected, resetting for clean demo ---"
  ipa-getcert stop-tracking -f /etc/pki/tls/certs/client.crt &>/dev/null || true
  ipa-client-install --uninstall --unattended
  rm -f /etc/pki/tls/certs/client.crt /etc/pki/tls/private/client.key
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

# ── Step 3: Request cert from IDM CA ─────────────────────────────────────────
echo ""
echo "=== Step 2: Request host certificate from IDM CA ==="
mkdir -p /etc/pki/tls/certs /etc/pki/tls/private

# certmonger tracks and auto-renews certs; ipa-getcert submits to IDM's CA
ipa-getcert request \
  -f /etc/pki/tls/certs/client.crt \
  -k /etc/pki/tls/private/client.key \
  -K host/client.demo.lab \
  -w  # wait for cert to be issued

echo "Certificate issued:"
openssl x509 -in /etc/pki/tls/certs/client.crt -noout -subject -issuer -dates

# Allow the calling user to read the cert and key
chown ec2-user:ec2-user /etc/pki/tls/certs/client.crt /etc/pki/tls/private/client.key
chmod 644 /etc/pki/tls/certs/client.crt
chmod 640 /etc/pki/tls/private/client.key

# ── Step 4: Vault login with cert ─────────────────────────────────────────────
echo ""
echo "=== Step 3: Authenticate to Vault using IDM-issued cert ==="
vault login \
  -method=cert \
  -ca-cert=/etc/ipa/ca.crt \
  -client-cert=/etc/pki/tls/certs/client.crt \
  -client-key=/etc/pki/tls/private/client.key \
  name=idm-clients

# ── Step 5: Read secret ───────────────────────────────────────────────────────
echo ""
echo "=== Step 4: Read secret from Vault ==="
vault kv get secret/demo/machine-secret

echo ""
echo "=== Demo complete ==="
