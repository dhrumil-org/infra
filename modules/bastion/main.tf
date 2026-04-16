################################################################################
# Bastion EC2 for DB Access (via AWS SSM Session Manager — no SSH keys, no port 22)
#
# Usage:
#   aws ssm start-session --target <instance-id> --region us-east-1
#
# Or port-forward RDS to localhost:
#   aws ssm start-session --target <instance-id> \
#     --document-name AWS-StartPortForwardingSessionToRemoteHost \
#     --parameters '{"host":["<rds-endpoint>"],"portNumber":["5432"],"localPortNumber":["5432"]}' \
#     --region us-east-1
################################################################################

################################################################################
# Latest Amazon Linux 2023 AMI
################################################################################

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

################################################################################
# Security Group — Bastion (no inbound, only egress)
################################################################################

resource "aws_security_group" "bastion" {
  name_prefix = "${var.project}-${var.env}-bastion-"
  description = "Security group for bastion EC2 (SSM only, no SSH)"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project}-${var.env}-bastion-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Bastion needs outbound HTTPS to reach SSM, ECR, and Secrets Manager
resource "aws_vpc_security_group_egress_rule" "bastion_https" {
  security_group_id = aws_security_group.bastion.id
  description       = "HTTPS for SSM, Secrets Manager, RDS API"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

# Bastion needs to reach RDS
resource "aws_vpc_security_group_egress_rule" "bastion_to_rds" {
  security_group_id            = aws_security_group.bastion.id
  description                  = "PostgreSQL to RDS"
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  referenced_security_group_id = var.rds_security_group_id
}

# Allow bastion SG into RDS SG
resource "aws_vpc_security_group_ingress_rule" "rds_from_bastion" {
  security_group_id            = var.rds_security_group_id
  description                  = "PostgreSQL from bastion"
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.bastion.id
}

################################################################################
# IAM Role — SSM Managed Instance + Secrets Manager read
################################################################################

resource "aws_iam_role" "bastion" {
  name = "${var.project}-${var.env}-bastion-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${var.project}-${var.env}-bastion-role"
  }
}

resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "bastion_secrets" {
  name = "${var.project}-${var.env}-bastion-secrets-read"
  role = aws_iam_role.bastion.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = var.master_secret_arn
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = var.secrets_kms_key_arn
      }
    ]
  })
}

resource "aws_iam_instance_profile" "bastion" {
  name = "${var.project}-${var.env}-bastion-profile"
  role = aws_iam_role.bastion.name
}

################################################################################
# EC2 Instance
################################################################################

resource "aws_instance" "bastion" {
  ami                    = data.aws_ssm_parameter.al2023_ami.value
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.bastion.id]
  iam_instance_profile   = aws_iam_instance_profile.bastion.name

  # No SSH key — SSM only
  associate_public_ip_address = false

  root_block_device {
    volume_type = "gp3"
    volume_size = 10
    encrypted   = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  user_data = <<-EOT
    #!/bin/bash
    set -e
    dnf update -y
    dnf install -y postgresql15 jq awscli
    echo "Bastion ready — use: aws ssm start-session --target $(ec2-metadata --instance-id | cut -d' ' -f2)"
  EOT

  tags = {
    Name = "${var.project}-${var.env}-bastion"
  }
}
