# =============================================================================
# Production Environment - EC2 Deployment (FREE TIER)
# =============================================================================
# 
# Deploys GitOps Demo app to AWS EC2 - FREE TIER ELIGIBLE
# Cost: $0/month (within free tier limits)
#
# Free Tier includes:
#   - 750 hours t2.micro/month (first 12 months)
#   - 30GB EBS storage
#   - 15GB data transfer out
#
# Usage:
#   cd terraform/environments/prod
#   terraform init
#   terraform plan
#   terraform apply
#
# =============================================================================

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "gitops-demo"
      Environment = "prod"
      ManagedBy   = "terraform"
    }
  }
}

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------

variable "aws_region" {
  default = "us-east-1"
}

variable "ssh_key_name" {
  description = "SSH key pair name (create in AWS Console first)"
  default     = ""
}

variable "my_ip" {
  description = "Your IP for SSH (run: curl ifconfig.me)"
  default     = "0.0.0.0/0"
}

variable "docker_image_tag" {
  default = "v1.0.1"
}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# -----------------------------------------------------------------------------
# VPC (Use Default VPC - FREE)
# -----------------------------------------------------------------------------

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# -----------------------------------------------------------------------------
# Security Group
# -----------------------------------------------------------------------------

resource "aws_security_group" "app" {
  name        = "gitops-demo-sg"
  description = "GitOps Demo app security group"
  vpc_id      = data.aws_vpc.default.id

  # HTTP access
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # App port (8080)
  ingress {
    description = "App port"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH access (restrict to your IP!)
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "gitops-demo-sg"
  }
}

# -----------------------------------------------------------------------------
# EC2 Instance (t2.micro - FREE TIER)
# -----------------------------------------------------------------------------

resource "aws_instance" "app" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t2.micro"  # FREE TIER!
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.app.id]
  associate_public_ip_address = true
  key_name                    = var.ssh_key_name != "" ? var.ssh_key_name : null

  # 8GB root volume (FREE: up to 30GB)
  root_block_device {
    volume_type           = "gp2"
    volume_size           = 8
    delete_on_termination = true
  }

  user_data = <<-EOF
    #!/bin/bash
    set -e
    
    # Log output
    exec > >(tee /var/log/user-data.log) 2>&1
    
    echo "=== Starting deployment ==="
    
    # Update and install Docker
    yum update -y
    amazon-linux-extras install docker -y
    systemctl start docker
    systemctl enable docker
    usermod -a -G docker ec2-user
    
    # Pull and run the app
    docker pull ghcr.io/anasadan/gitops-demo:${var.docker_image_tag}
    
    # Run on port 80 (no need for ALB!)
    docker run -d \
      --name gitops-demo \
      --restart always \
      -p 80:8080 \
      -e ENVIRONMENT=production \
      -e SERVICE_NAME=gitops-demo \
      ghcr.io/anasadan/gitops-demo:${var.docker_image_tag}
    
    echo "=== Deployment complete ==="
    echo "App running on port 80"
  EOF

  tags = {
    Name = "gitops-demo-prod"
  }
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "instance_id" {
  value = aws_instance.app.id
}

output "public_ip" {
  value = aws_instance.app.public_ip
}

output "public_dns" {
  value = aws_instance.app.public_dns
}

output "app_url" {
  value = "http://${aws_instance.app.public_ip}"
}

output "health_url" {
  value = "http://${aws_instance.app.public_ip}/health"
}

output "version_url" {
  value = "http://${aws_instance.app.public_ip}/version"
}

output "ssh_command" {
  value = var.ssh_key_name != "" ? "ssh -i ~/.ssh/${var.ssh_key_name}.pem ec2-user@${aws_instance.app.public_ip}" : "SSH key not configured"
}

output "estimated_cost" {
  value = "FREE (within AWS Free Tier limits)"
}
