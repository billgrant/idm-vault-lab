# ── AMI ──────────────────────────────────────────────────────────────────────
# IBM-internal approved RHEL 9 image with EDR pre-installed.
# Owner 888995627335 is the IBM ami-prod account — this AMI is not publicly
# available, so this branch is not suitable for external use.
data "aws_ami" "rhel9" {
  most_recent = true
  owners      = ["888995627335"] # IBM ami-prod account

  filter {
    name   = "name"
    values = ["hc-base-rhel-9-x86_64-*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# ── VPC ───────────────────────────────────────────────────────────────────────
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "idm-vault-lab" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "idm-vault-lab" }
}

resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"

  tags = { Name = "idm-vault-lab" }
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "idm-vault-lab" }
}

resource "aws_route_table_association" "main" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.main.id
}

# ── Route53 private hosted zone ───────────────────────────────────────────────
resource "aws_route53_zone" "demo_lab" {
  name = "demo.lab"

  vpc {
    vpc_id = aws_vpc.main.id
  }

  tags = { Name = "idm-vault-lab" }
}

resource "aws_route53_record" "idm" {
  zone_id = aws_route53_zone.demo_lab.zone_id
  name    = "idm.demo.lab"
  type    = "A"
  ttl     = 60
  records = [aws_instance.idm.private_ip]
}

resource "aws_route53_record" "vault" {
  zone_id = aws_route53_zone.demo_lab.zone_id
  name    = "vault.demo.lab"
  type    = "A"
  ttl     = 60
  records = [aws_instance.vault.private_ip]
}

resource "aws_route53_record" "client" {
  zone_id = aws_route53_zone.demo_lab.zone_id
  name    = "client.demo.lab"
  type    = "A"
  ttl     = 60
  records = [aws_instance.client.private_ip]
}

# ── Security Groups ───────────────────────────────────────────────────────────

# Allow all traffic between the three lab instances
resource "aws_security_group" "internal" {
  name        = "idm-vault-lab-internal"
  description = "Allow all traffic within the lab VPC"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "idm" {
  name        = "idm-vault-lab-idm"
  description = "IDM server inbound rules"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "LDAP"
    from_port   = 389
    to_port     = 389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "LDAPS"
    from_port   = 636
    to_port     = 636
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Kerberos TCP"
    from_port   = 88
    to_port     = 88
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Kerberos UDP"
    from_port   = 88
    to_port     = 88
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Kerberos change password"
    from_port   = 464
    to_port     = 464
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "vault" {
  name        = "idm-vault-lab-vault"
  description = "Vault server inbound rules"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Vault API"
    from_port   = 8200
    to_port     = 8200
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "client" {
  name        = "idm-vault-lab-client"
  description = "Client VM inbound rules"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ── KMS key for Vault auto-unseal ────────────────────────────────────────────
resource "aws_kms_key" "vault" {
  description             = "Vault auto-unseal key"
  deletion_window_in_days = 7

  tags = { Name = "idm-vault-lab-unseal" }
}

resource "aws_kms_alias" "vault" {
  name          = "alias/idm-vault-lab-unseal"
  target_key_id = aws_kms_key.vault.key_id
}

# ── IAM role for Vault EC2 instance ──────────────────────────────────────────
data "aws_iam_policy_document" "vault_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "vault_kms" {
  statement {
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:DescribeKey",
    ]
    resources = [aws_kms_key.vault.arn]
  }
}

resource "aws_iam_role" "vault" {
  name               = "idm-vault-lab-vault"
  assume_role_policy = data.aws_iam_policy_document.vault_assume_role.json
}

resource "aws_iam_role_policy" "vault_kms" {
  name   = "vault-kms-unseal"
  role   = aws_iam_role.vault.id
  policy = data.aws_iam_policy_document.vault_kms.json
}

resource "aws_iam_instance_profile" "vault" {
  name = "idm-vault-lab-vault"
  role = aws_iam_role.vault.name
}

# ── EC2 Instances ─────────────────────────────────────────────────────────────

resource "aws_instance" "idm" {
  ami                    = data.aws_ami.rhel9.id
  instance_type          = "t3.medium"
  subnet_id              = aws_subnet.main.id
  key_name               = var.key_pair_name
  vpc_security_group_ids = [aws_security_group.idm.id, aws_security_group.internal.id]

  # IDM needs a fixed private IP so DNS records are stable during bootstrap
  private_ip = "10.0.1.10"

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/userdata/idm-server.sh", {
    rh_username        = var.rh_username
    rh_password        = var.rh_password
    idm_admin_password = var.idm_admin_password
    idm_ds_password    = var.idm_ds_password
  })

  tags = { Name = "idm-server" }
}

resource "aws_instance" "vault" {
  ami                    = data.aws_ami.rhel9.id
  instance_type          = "t3.small"
  subnet_id              = aws_subnet.main.id
  key_name               = var.key_pair_name
  vpc_security_group_ids = [aws_security_group.vault.id, aws_security_group.internal.id]
  iam_instance_profile   = aws_iam_instance_profile.vault.name

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/userdata/vault-server.sh", {
    vault_license  = var.vault_license
    kms_key_id     = aws_kms_key.vault.key_id
    aws_region     = var.aws_region
  })

  tags = { Name = "vault-server" }
}

resource "aws_instance" "client" {
  ami                    = data.aws_ami.rhel9.id
  instance_type          = "t3.small"
  subnet_id              = aws_subnet.main.id
  key_name               = var.key_pair_name
  vpc_security_group_ids = [aws_security_group.client.id, aws_security_group.internal.id]

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/userdata/client.sh", {
    rh_username = var.rh_username
    rh_password = var.rh_password
  })

  tags = { Name = "client-vm" }
}
