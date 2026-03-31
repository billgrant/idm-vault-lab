output "idm_public_ip" {
  description = "Public IP of the IDM server"
  value       = aws_instance.idm.public_ip
}

output "vault_public_ip" {
  description = "Public IP of the Vault server"
  value       = aws_instance.vault.public_ip
}

output "client_public_ip" {
  description = "Public IP of the client VM"
  value       = aws_instance.client.public_ip
}

output "vault_addr" {
  description = "Vault API address (for vault-config and demo.sh)"
  value       = "https://${aws_instance.vault.public_ip}:8200"
}

output "ssh_idm" {
  description = "SSH command for IDM server"
  value       = "ssh -i ~/.ssh/${var.key_pair_name}.pem ec2-user@${aws_instance.idm.public_ip}"
}

output "ssh_vault" {
  description = "SSH command for Vault server"
  value       = "ssh -i ~/.ssh/${var.key_pair_name}.pem ec2-user@${aws_instance.vault.public_ip}"
}

output "ssh_client" {
  description = "SSH command for client VM"
  value       = "ssh -i ~/.ssh/${var.key_pair_name}.pem ec2-user@${aws_instance.client.public_ip}"
}

output "kms_key_id" {
  description = "KMS key ID used for Vault auto-unseal"
  value       = aws_kms_key.vault.key_id
}

output "next_steps" {
  description = "What to do after terraform apply"
  value       = <<-EOT
    Next steps:
    1. Wait ~15 min for IDM to finish bootstrapping
       Check: ssh ec2-user@${aws_instance.idm.public_ip} 'cat ~/idm-ready'
    2. Vault is auto-unsealed via KMS — no manual unseal needed
       SSH to Vault: ${aws_instance.vault.public_ip}
       Run: cat ~/vault-init.json   (save the root token and recovery keys)
    3. cd ../vault-config && terraform apply
       (pass idm_ca_cert, vault_addr, vault_token as variables)
    4. SSH to client, run: sudo bash demo.sh <vault_public_ip> <idm_admin_password>
  EOT
}
