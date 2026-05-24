terraform {
  required_version = ">=1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "~> 2.2"
    }
  }
}

provider "cloudinit" {}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      project   = "sheesh-box-e2e"
      env       = "e2e"
      managedBy = "terraform"
    }
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Exercises the module under test against the default VPC.
module "sheesh" {
  source = "../../../terraform"

  name_prefix    = var.name_prefix
  ami_id         = var.ami_id
  vpc_id         = data.aws_vpc.default.id
  subnet_id      = data.aws_subnets.default.ids[0]
  dns_domain     = var.dns_domain
  hostname       = local.hostname
  github_org     = var.github_org
  content_repo   = var.content_repo
  content_branch = var.content_branch
  acme_email     = var.acme_email

  # E2E-friendly settings: staging certs (avoid LE rate limits) and a
  # destroyable data volume.
  acme_staging                = true
  imdsv2_enabled              = true
  data_volume_prevent_destroy = false
}

# The module reads the content git-sync deploy key from this SSM SecureString at
# the hardcoded path (config-parameter-store.tf -> local.content_deploy_key_arn);
# the test seeds it from SHEESH_TEST_DEPLOY_KEY.
resource "aws_ssm_parameter" "content_deploy_key" {
  name        = "/${var.name_prefix}/content-deploy-key/contents"
  description = "${var.name_prefix} content git-sync deploy key"
  type        = "SecureString"
  tier        = "Standard"
  value       = var.deploy_key
}

variable "ami_id" {
  type = string
}

variable "name_prefix" {
  type = string
}

variable "hostname" {
  type    = string
  default = ""
}

variable "aws_region" {
  type    = string
  default = "ap-southeast-1"
}

variable "dns_domain" {
  description = "A Route53 zone present in the test account"
  type        = string
}

variable "github_org" {
  type = string
}

variable "content_repo" {
  type = string
}

variable "content_branch" {
  type    = string
  default = "main"
}

variable "acme_email" {
  type    = string
  default = "e2e@sheesh.host"
}

variable "deploy_key" {
  description = "PEM private deploy key with read access to the content repo"
  type        = string
  sensitive   = true
}

locals {
  hostname = length(var.hostname) == 0 ? "sheesh-${var.name_prefix}" : var.hostname
}

output "asg_name" {
  value = module.sheesh.asg_name
}

output "role_arn" {
  value = module.sheesh.role_arn
}
