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

output "idm_bootstrap_log" {
  description = "Stream the IDM bootstrap log — useful for watching progress in real time"
  value       = "ssh -i ~/.ssh/${var.key_pair_name}.pem ec2-user@${aws_instance.idm.public_ip} 'tail -f /var/log/idm-bootstrap.log'"
}

output "idm_ca_cert_command" {
  description = "Retrieve the IDM CA cert — paste the output into vault-config/terraform.auto.tfvars"
  value       = "ssh -i ~/.ssh/${var.key_pair_name}.pem ec2-user@${aws_instance.idm.public_ip} 'cat ~/idm-ca.crt'"
}

output "scp_demo_sh" {
  description = "Copy demo.sh to the client VM before running it"
  value       = "scp -i ~/.ssh/${var.key_pair_name}.pem scripts/demo.sh ec2-user@${aws_instance.client.public_ip}:~/"
}

output "kms_key_id" {
  description = "KMS key ID used for Vault auto-unseal"
  value       = aws_kms_key.vault.key_id
}

output "next_steps" {
  description = "What to do after terraform apply"
  value       = <<-EOT
    Next steps:
    1. Watch IDM bootstrap (takes ~15 min):
       ssh -i ~/.ssh/${var.key_pair_name}.pem ec2-user@${aws_instance.idm.public_ip} 'tail -f /var/log/idm-bootstrap.log'
       Done when you see: idm-ready

    2. Save Vault credentials (auto-unsealed via KMS — no manual unseal needed):
       ssh -i ~/.ssh/${var.key_pair_name}.pem ec2-user@${aws_instance.vault.public_ip} 'cat ~/vault-init.json'

    3. Configure Vault:
       Run idm_ca_cert_command output to get the CA cert, then:
       cd ../vault-config
       VAULT_SKIP_VERIFY=true terraform apply

    4. Copy demo.sh and run it:
       scp -i ~/.ssh/${var.key_pair_name}.pem scripts/demo.sh ec2-user@${aws_instance.client.public_ip}:~/
       ssh -i ~/.ssh/${var.key_pair_name}.pem ec2-user@${aws_instance.client.public_ip}
       sudo bash demo.sh ${aws_instance.vault.public_ip} <idm_admin_password>
  EOT
}
