variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "key_pair_name" {
  description = "Name of the EC2 key pair for SSH access"
  type        = string
  default     = "billgrant"
}

variable "rh_username" {
  description = "Red Hat Developer Portal username for subscription-manager"
  type        = string
  sensitive   = true
}

variable "rh_password" {
  description = "Red Hat Developer Portal password for subscription-manager"
  type        = string
  sensitive   = true
}

variable "idm_admin_password" {
  description = "IPA admin user password (min 8 chars)"
  type        = string
  sensitive   = true
}

variable "idm_ds_password" {
  description = "IPA Directory Server password (min 8 chars)"
  type        = string
  sensitive   = true
}

variable "vault_license" {
  description = "Vault Enterprise license string"
  type        = string
  sensitive   = true
}
