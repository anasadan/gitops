# =============================================================================
# Production Environment - EC2 Deployment
# =============================================================================
# 
# Deploy your GitOps Demo app to AWS EC2
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

  # Uncomment to use S3 backend for state
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "gitops-demo/prod/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-lock"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "gitops-demo"
      Environment = "prod"
      ManagedBy   = "terraform"
      Repository  = "github.com/anasadan/gitops"
    }
  }
}

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "ssh_key_name" {
  description = "Name of existing SSH key pair (leave empty to skip)"
  type        = string
  default     = ""
}

variable "my_ip" {
  description = "Your IP address for SSH access (e.g., 1.2.3.4/32)"
  type        = string
  default     = "0.0.0.0/0"  # Restrict this!
}

variable "docker_image_tag" {
  description = "Docker image tag to deploy"
  type        = string
  default     = "v1.0.1"
}

# -----------------------------------------------------------------------------
# Deploy Application
# -----------------------------------------------------------------------------

module "app" {
  source = "../../modules/ec2-app"

  app_name     = "gitops-demo"
  environment  = "prod"
  aws_region   = var.aws_region

  # Instance configuration
  instance_type  = "t3.small"      # Upgrade for production
  instance_count = 2               # 2 instances for HA

  # Docker image from GHCR
  docker_image = "ghcr.io/anasadan/gitops-demo:${var.docker_image_tag}"
  app_port     = 8080

  # SSH access (optional)
  ssh_key_name     = var.ssh_key_name
  allowed_ssh_cidr = var.my_ip

  # Networking
  vpc_cidr = "10.0.0.0/16"

  tags = {
    Owner = "anasadan"
  }
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "app_url" {
  description = "URL to access the application"
  value       = module.app.alb_url
}

output "alb_dns" {
  description = "ALB DNS name"
  value       = module.app.alb_dns_name
}

output "instance_ips" {
  description = "EC2 instance public IPs"
  value       = module.app.instance_public_ips
}

output "health_check_url" {
  description = "Health check endpoint"
  value       = "${module.app.alb_url}/health"
}

output "version_url" {
  description = "Version endpoint"
  value       = "${module.app.alb_url}/version"
}

