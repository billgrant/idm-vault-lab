# ── KV v2 secrets engine ──────────────────────────────────────────────────────
resource "vault_mount" "secret" {
  path        = "secret"
  type        = "kv-v2"
  description = "KV v2 for demo secrets"
}

# ── Secrets ───────────────────────────────────────────────────────────────────
resource "vault_kv_secret_v2" "web_secret" {
  mount = vault_mount.secret.path
  name  = "web/app-config"

  data_json = jsonencode({
    api_endpoint = "https://api.internal.demo.lab"
    api_key      = "web-svc-key-7f3a9b"
    environment  = "production"
  })
}

resource "vault_kv_secret_v2" "db_secret" {
  mount = vault_mount.secret.path
  name  = "db/credentials"

  data_json = jsonencode({
    db_host     = "postgres.internal.demo.lab"
    db_user     = "app_svc"
    db_password = "db-svc-pass-c4e81d"
    db_name     = "appdb"
  })
}

# ── Policies ──────────────────────────────────────────────────────────────────
resource "vault_policy" "web_server" {
  name = "web-server-policy"

  policy = <<-EOT
    path "secret/data/web/*" {
      capabilities = ["read"]
    }
  EOT
}

resource "vault_policy" "db_server" {
  name = "db-server-policy"

  policy = <<-EOT
    path "secret/data/db/*" {
      capabilities = ["read"]
    }
  EOT
}

# ── Cert auth method ──────────────────────────────────────────────────────────
resource "vault_auth_backend" "cert" {
  type        = "cert"
  description = "TLS cert auth — trusts certs issued by Red Hat IDM CA"
}

# ── Cert auth roles ───────────────────────────────────────────────────────────
# Policy is assigned by OU — no per-hostname config needed.
# The OU is stamped by the IDM cert profile, not the client.
# CA ACLs on the IDM side enforce which host groups can use which profile.
resource "vault_cert_auth_backend_role" "web_servers" {
  name        = "web-servers"
  certificate = var.idm_ca_cert
  backend     = vault_auth_backend.cert.path

  token_policies               = [vault_policy.web_server.name]
  token_ttl                    = 3600
  allowed_organizational_units = ["web-servers"]
}

resource "vault_cert_auth_backend_role" "db_servers" {
  name        = "db-servers"
  certificate = var.idm_ca_cert
  backend     = vault_auth_backend.cert.path

  token_policies               = [vault_policy.db_server.name]
  token_ttl                    = 3600
  allowed_organizational_units = ["db-servers"]
}
