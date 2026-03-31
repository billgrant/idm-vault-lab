variable "vault_addr" {
  description = "Vault API address (e.g. http://<public-ip>:8200)"
  type        = string
}

variable "vault_token" {
  description = "Vault root token (from vault-init.json on the Vault server)"
  type        = string
  sensitive   = true
}

variable "idm_ca_cert" {
  description = "Contents of the IDM CA cert (cat ~/idm-ca.crt on the IDM server)"
  type        = string
}
