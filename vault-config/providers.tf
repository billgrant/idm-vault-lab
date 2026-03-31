terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.8"
    }
  }
  required_version = ">= 1.5"
}

provider "vault" {
  address = var.vault_addr
  token   = var.vault_token
}
