#!/bin/bash
set -euxo pipefail
exec > >(tee /var/log/client-bootstrap.log) 2>&1

# ── Red Hat subscription ───────────────────────────────────────────────────────
subscription-manager register \
  --username='${rh_username}' \
  --password='${rh_password}' \
  --auto-attach

# ── Set hostname ───────────────────────────────────────────────────────────────
hostnamectl set-hostname client.demo.lab

# ── Install IPA client and Vault CLI ──────────────────────────────────────────
dnf install -y ipa-client

yum install -y yum-utils
yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
yum install -y vault

echo "Client bootstrap complete" > /home/ec2-user/client-ready
