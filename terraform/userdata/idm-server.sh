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

# ── Cert profiles and CA ACLs for role-based machine identity ─────────────────
# The default caIPAserviceCert profile always issues CN=<hostname>, O=<REALM>.
# We create two derived profiles that additionally stamp an OU into the subject,
# then bind each profile to a host group via CA ACLs. Any host in that group
# can ONLY use that group's profile — enforced server-side by Dogtag.
echo '${idm_admin_password}' | kinit admin

# Export the default service cert profile as the base for both custom profiles
ipa certprofile-show caIPAserviceCert --out=/tmp/caIPAserviceCert.cfg

# webServersCert — inserts OU=web-servers after the CN in the subject
sed -E \
  -e 's/^profileId=.*/profileId=webServersCert/' \
  -e 's/(default\.params\.name=CN=)([^,]*)/\1\2, OU=web-servers/' \
  /tmp/caIPAserviceCert.cfg > /tmp/webServersCert.cfg
ipa certprofile-import webServersCert \
  --file=/tmp/webServersCert.cfg \
  --desc="Web tier — stamps OU=web-servers in cert subject" \
  --store=true

# dbServersCert — inserts OU=db-servers after the CN in the subject
sed -E \
  -e 's/^profileId=.*/profileId=dbServersCert/' \
  -e 's/(default\.params\.name=CN=)([^,]*)/\1\2, OU=db-servers/' \
  /tmp/caIPAserviceCert.cfg > /tmp/dbServersCert.cfg
ipa certprofile-import dbServersCert \
  --file=/tmp/dbServersCert.cfg \
  --desc="DB tier — stamps OU=db-servers in cert subject" \
  --store=true

# Host groups — machines are members, not individual CNs
ipa hostgroup-add web-servers --desc="Web tier — entitled to webServersCert profile"
ipa hostgroup-add db-servers  --desc="DB tier — entitled to dbServersCert profile"

# CA ACLs — bind each host group to exactly one cert profile
# A host in web-servers cannot request a dbServersCert and vice versa
ipa caacl-add web-servers-acl --desc="Web tier cert issuance policy"
ipa caacl-add-profile web-servers-acl --certprofiles=webServersCert
ipa caacl-add-host    web-servers-acl --hostgroups=web-servers

ipa caacl-add db-servers-acl --desc="DB tier cert issuance policy"
ipa caacl-add-profile db-servers-acl --certprofiles=dbServersCert
ipa caacl-add-host    db-servers-acl --hostgroups=db-servers

kdestroy

echo "IDM bootstrap complete" > /home/ec2-user/idm-ready
