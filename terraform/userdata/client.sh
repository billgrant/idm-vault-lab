#!/bin/bash
set -euxo pipefail
exec > >(tee /var/log/client-bootstrap.log) 2>&1

# ── Red Hat subscription ───────────────────────────────────────────────────────
# Skip if already registered (e.g. pre-subscribed IBM internal images)
if ! subscription-manager status &>/dev/null; then
  subscription-manager register \
    --username='${rh_username}' \
    --password='${rh_password}' \
    --auto-attach
fi

# ── Set hostname ───────────────────────────────────────────────────────────────
hostnamectl set-hostname client.demo.lab

# ── Install IPA client and Vault CLI ──────────────────────────────────────────
dnf install -y ipa-client

yum install -y yum-utils
yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
yum install -y vault

echo "Client bootstrap complete" > /home/ec2-user/client-ready
