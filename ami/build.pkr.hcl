packer {
  required_version = "~> 1.9"
  # https://www.packer.io/plugins/builders/amazon
  required_plugins {
    amazon = {
      version = "~> 1.2"
      source  = "github.com/hashicorp/amazon"
    }
    git = {
      version = "~> 0.3.2"
      source  = "github.com/ethanmdavidson/git"
    }
    amazon-ami-management = {
      version = "~> 1.4.1"
      source  = "github.com/wata727/amazon-ami-management"
    }
  }
}

variable "pr" {
  description = "Indicate if AMI was built from a PR"
  type        = bool
  default     = false
}

variable "aws_region" {
  description = "The AWS region for source AMI and output AMI"
  type        = string
  default     = "ap-southeast-1"
}

variable "ami_regions" {
  description = "The AWS Regions to publish the AMI to"
  type        = list(string)
  default     = []
}

variable "ami_org_arns" {
  description = "The AWS Organizations to publish the AMI to"
  type        = list(string)
  default     = []
}

variable "vpc_id" {
  description = "The VPC for EC2 image build"
  type        = string
}

variable "subnet_id" {
  description = "The subnet for EC2 image build"
  type        = string
}

variable "instance_type" {
  description = "Instance type to build ami on"
  type        = string
  default     = "t4g.large"
}

variable "confd_version" {
  description = "confd version"
  # https://github.com/abtreece/confd/releases
  type    = string
  default = "0.30.0"
}

variable "caddy_version" {
  description = "caddy version"
  # https://github.com/caddyserver/caddy/releases
  type    = string
  default = "2.9.1"
}

variable "git_sync_version" {
  description = "git-sync version"
  # https://github.com/kubernetes/git-sync/releases
  type    = string
  default = "4.4.0"
}

data "git-commit" "head" {}

locals {
  truncated_sha = substr(data.git-commit.head.hash, 0, 8)
  author        = data.git-commit.head.author
  identifier    = "packer-%{if var.pr}pr-%{endif}sheesh"
  ami_name      = "${local.identifier}-${local.truncated_sha}"
}

data "amazon-ami" "ubuntu" {
  filters = {
    name                = "ubuntu/images/*ubuntu-noble-24.04-arm64-server-*"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["099720109477"]
  region      = var.aws_region
}

source "amazon-ebs" "ubuntu" {
  # output ami name
  ami_name              = local.ami_name
  force_deregister      = true
  force_delete_snapshot = true
  ami_description       = "sheesh.host box AMI, built from a commit by ${local.author}"
  instance_type         = var.instance_type
  region                = var.aws_region
  vpc_id                = var.vpc_id
  subnet_id             = var.subnet_id
  source_ami            = data.amazon-ami.ubuntu.id
  ssh_username          = "ubuntu"
  communicator          = "ssh"
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
  tags = {
    OS_Version                       = "Ubuntu"
    Base_AMI_ID                      = "{{ .SourceAMI }}"
    Base_AMI_Name                    = "{{ .SourceAMIName }}"
    App                              = "Sheesh"
    Amazon_AMI_Management_Identifier = local.identifier
  }

  launch_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 8
    volume_type           = "gp3"
  }

  # publish to additional regions / AWS Organizations
  ami_regions  = var.ami_regions
  ami_org_arns = var.ami_org_arns
}

build {
  sources = ["source.amazon-ebs.ubuntu"]

  # https://www.packer.io/docs/debugging#issues-installing-ubuntu-packages
  provisioner "shell" {
    inline = ["cloud-init status --wait"]
  }

  provisioner "shell" {
    inline = [
      "sudo mkdir -p /tmp/build-assets /opt/sheesh/shared",
      "sudo chown ubuntu:ubuntu /tmp/build-assets /opt/sheesh/shared"
    ]
  }

  # Per-service runtime assets (caddy, git-sync, confd).
  provisioner "file" {
    source      = "assets/"
    destination = "/tmp/build-assets"
  }

  # Shared boot scripts (attach-ebs, associate-address, functions).
  provisioner "file" {
    source      = "../shared/"
    destination = "/opt/sheesh/shared"
  }

  provisioner "shell" {
    # https://www.packer.io/docs/provisioners/shell#sudo-example
    script = "scripts/install-confd.sh"
    environment_vars = [
      "CONFD_VERSION=v${var.confd_version}",
    ]
    execute_command = "chmod +x {{ .Path }}; sudo env {{ .Vars }} {{ .Path }}"
  }

  provisioner "shell" {
    script = "scripts/install-caddy.sh"
    # NOTE: version is passed without "v" prefix
    environment_vars = [
      "CADDY_VERSION=${var.caddy_version}",
    ]
    execute_command = "chmod +x {{ .Path }}; sudo env {{ .Vars }} {{ .Path }}"
  }

  provisioner "shell" {
    script = "scripts/install-git-sync.sh"
    environment_vars = [
      "GIT_SYNC_VERSION=v${var.git_sync_version}",
    ]
    execute_command = "chmod +x {{ .Path }}; sudo env {{ .Vars }} {{ .Path }}"
  }

  post-processor "amazon-ami-management" {
    # https://github.com/wata727/packer-plugin-amazon-ami-management#usage
    # plugin will skip images in use across Instances, LaunchConfigurations and LaunchTemplates
    regions       = [var.aws_region]
    identifier    = local.identifier
    keep_releases = 3
  }

  post-processor "manifest" {
    output     = "manifest.json"
    strip_path = true
  }
}
