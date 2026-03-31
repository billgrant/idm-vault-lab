# ── KV v2 secrets engine ──────────────────────────────────────────────────────
resource "vault_mount" "secret" {
  path        = "secret"
  type        = "kv-v2"
  description = "KV v2 for demo secrets"
}

# ── Demo secret ───────────────────────────────────────────────────────────────
resource "vault_kv_secret_v2" "machine_secret" {
  mount = vault_mount.secret.path
  name  = "demo/machine-secret"

  data_json = jsonencode({
    api_key     = "demo-api-key-abc123"
    environment = "production"
    issued_by   = "Red Hat IDM"
  })
}

# ── Policy ────────────────────────────────────────────────────────────────────
resource "vault_policy" "idm_client" {
  name = "idm-client-policy"

  policy = <<-EOT
    # IDM-enrolled machines may read demo secrets
    path "secret/data/demo/*" {
      capabilities = ["read"]
    }
  EOT
}

# ── Cert auth method ──────────────────────────────────────────────────────────
resource "vault_auth_backend" "cert" {
  type        = "cert"
  description = "TLS cert auth — trusts certs issued by Red Hat IDM CA"
}

# ── Cert auth role ────────────────────────────────────────────────────────────
# Any cert signed by the IDM CA will match this role and receive the policy.
resource "vault_cert_auth_backend_role" "idm_clients" {
  name        = "idm-clients"
  certificate = var.idm_ca_cert
  backend     = vault_auth_backend.cert.path

  token_policies = [vault_policy.idm_client.name]
  token_ttl      = 3600
}
