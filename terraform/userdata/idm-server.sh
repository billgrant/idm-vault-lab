#!/bin/bash
set -euxo pipefail
exec > >(tee /var/log/idm-bootstrap.log) 2>&1

# ── Red Hat subscription ───────────────────────────────────────────────────────
# Skip if already registered (e.g. pre-subscribed IBM internal images)
if ! subscription-manager status &>/dev/null; then
  subscription-manager register \
    --username='${rh_username}' \
    --password='${rh_password}' \
    --auto-attach
fi

# ── Install IDM packages ───────────────────────────────────────────────────────
dnf install -y ipa-server ipa-server-dns

# ── Set hostname (required before ipa-server-install) ─────────────────────────
# Both hostnamectl AND /etc/hosts must agree — ipa-server-install checks both
hostnamectl set-hostname idm.demo.lab
echo "10.0.1.10 idm.demo.lab idm" >> /etc/hosts

# ── Install IDM server ────────────────────────────────────────────────────────
# --no-ntp: AWS uses chrony, no need for IPA to manage NTP
ipa-server-install \
  --unattended \
  --realm=DEMO.LAB \
  --domain=demo.lab \
  --hostname=idm.demo.lab \
  --ds-password='${idm_ds_password}' \
  --admin-password='${idm_admin_password}' \
  --no-ntp

# ── Export CA cert ─────────────────────────────────────────────────────────────
cp /etc/ipa/ca.crt /home/ec2-user/idm-ca.crt
chmod 644 /home/ec2-user/idm-ca.crt

echo "IDM bootstrap complete" > /home/ec2-user/idm-ready
