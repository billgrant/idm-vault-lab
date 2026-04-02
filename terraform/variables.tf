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

variable "ami_owner" {
  description = "AWS account ID that owns the RHEL 9 AMI"
  type        = string
  default     = "309956199498" # Red Hat official — override for internal images
}

variable "ami_name_pattern" {
  description = "Name filter pattern for the RHEL 9 AMI"
  type        = string
  default     = "RHEL-9*GA*" # override for internal images e.g. hc-base-rhel-9-x86_64-*
}
