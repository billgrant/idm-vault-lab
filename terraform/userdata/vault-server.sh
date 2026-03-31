#!/bin/bash
set -euxo pipefail
exec > >(tee /var/log/vault-bootstrap.log) 2>&1

# ── Install Vault Enterprise ───────────────────────────────────────────────────
yum install -y yum-utils
yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
yum install -y vault-enterprise

# ── Write license ──────────────────────────────────────────────────────────────
cat > /etc/vault.d/vault.hclic <<'LICEOF'
${vault_license}
LICEOF
chmod 640 /etc/vault.d/vault.hclic
chown root:vault /etc/vault.d/vault.hclic

# ── Generate self-signed TLS cert for Vault listener ─────────────────────────
# Vault cert auth requires TLS on the listener — the client certificate is
# presented during the mutual TLS handshake.
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
openssl req -x509 -newkey rsa:4096 \
  -keyout /etc/vault.d/vault-key.pem \
  -out /etc/vault.d/vault-cert.pem \
  -days 365 -nodes \
  -subj "/CN=vault.demo.lab/O=DEMO.LAB" \
  -addext "subjectAltName=DNS:vault.demo.lab,IP:$PRIVATE_IP"
chown vault:vault /etc/vault.d/vault-cert.pem /etc/vault.d/vault-key.pem
chmod 640 /etc/vault.d/vault-key.pem

# Make the cert available for clients to copy
cp /etc/vault.d/vault-cert.pem /home/ec2-user/vault-cert.pem
chmod 644 /home/ec2-user/vault-cert.pem

# ── Write vault.hcl ───────────────────────────────────────────────────────────
# AWS KMS auto-unseal: the EC2 instance profile grants kms:Encrypt/Decrypt
# so Vault unseals itself on start without any manual key input.
cat > /etc/vault.d/vault.hcl <<HCLEOF
ui            = true
disable_mlock = true

storage "file" {
  path = "/opt/vault/data"
}

listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_cert_file = "/etc/vault.d/vault-cert.pem"
  tls_key_file  = "/etc/vault.d/vault-key.pem"
}

seal "awskms" {
  region     = "${aws_region}"
  kms_key_id = "${kms_key_id}"
}

license_path = "/etc/vault.d/vault.hclic"
HCLEOF

mkdir -p /opt/vault/data
chown -R vault:vault /opt/vault

# ── Start Vault ────────────────────────────────────────────────────────────────
systemctl enable vault
systemctl start vault

# ── Initialize Vault ──────────────────────────────────────────────────────────
# With KMS auto-unseal, init produces recovery keys (not unseal keys) and
# Vault comes up unsealed automatically.
sleep 10
export VAULT_ADDR="https://127.0.0.1:8200"
export VAULT_SKIP_VERIFY=true
vault operator init -format=json > /home/ec2-user/vault-init.json
chmod 600 /home/ec2-user/vault-init.json
chown ec2-user:ec2-user /home/ec2-user/vault-init.json

echo "Vault bootstrap complete" > /home/ec2-user/vault-ready
