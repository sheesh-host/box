variable "name_prefix" {
  description = "name prefix for resources created"
  type        = string
}

variable "hour_to_scale_up" {
  description = "UTC hour for ASG scheduled scale up (MON-FRI) - Default is 7am SGT"
  type        = number
  default     = 23 # -> 7 am Singapore time
}

variable "hour_to_scale_down" {
  description = "UTC hour for ASG scheduled scale down (every day) - Default is 8pm SGT"
  type        = string
  default     = 12 # -> 8 pm Singapore time
}

variable "ami_id" {
  description = "AMI to deploy"
  type        = string
}

variable "vpc_id" {
  description = "VPC to deploy"
  type        = string
}

variable "subnet_id" {
  description = "Subnet to deploy"
  type        = string
}

variable "instance_type" {
  description = "EC2 Instance type"
  type        = string
  default     = "t4g.small"
}

variable "dns_domain" {
  description = "DNS Zone to create host record in"
  type        = string
}

variable "hostname" {
  description = "The hostname for the Sheesh Host to create in the dns_domain"
  type        = string
}

variable "github_org" {
  description = "The GitHub Org that owns the content repository"
  type        = string
}

variable "content_repo" {
  description = "The GitHub repository under github_org that holds the static content"
  type        = string
}

variable "content_branch" {
  description = "git branch in the content_repo to track and serve"
  type        = string
  default     = "main"
}

variable "acme_email" {
  description = "email used for LetsEncrypt certificates"
  type        = string
}

variable "acme_staging" {
  description = "Use Let's Encrypt Staging environment"
  type        = bool
  default     = false
}

# note:
# existing attached policies hardcoded in module:
# - AmazonSSMManagedInstanceCore: to manage node through System Manager
variable "additional_attached_policy_arns" {
  description = "Additional policy ARNs to attach to Instance role"
  type        = list(string)
  default     = []
}

# note:
# https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_iam-quotas.html#reference_iam-quotas-entity-length
# existing inline policies hardcoded in module:
# - ebs attach policy:      attach EBS volume to itself
# - eip associate policy:   associate the EIP to itself
# - parameter store policy: read the box's SSM config
variable "additional_inline_policies" {
  description = "Additional inline policies for Instance role"
  type = map(object({
    policy = map(object({
      effect        = optional(string, "Allow")
      actions       = list(string)
      resources     = optional(list(string))
      not_resources = optional(list(string))
      conditions = optional(list(object({
        test     = string
        variable = string
        values   = list(string)
      })), [])
    }))
  }))
  default = {}
}

variable "tags" {
  description = "Resource tags"
  type = map(object({
    value               = string
    propagate_at_launch = optional(bool)
  }))
  default = {}
}

variable "root_volume_type" {
  description = "Root volume type"
  type        = string
  default     = "gp3"
}

variable "root_volume_size" {
  description = "Root volume size"
  type        = number
  default     = 8
}

variable "data_volume_prevent_destroy" {
  description = "Prevent EBS volume from being destroyed on instance termination"
  type        = bool
  default     = true
}

variable "data_volume_type" {
  description = "Data EBS Volume type"
  type        = string
  default     = "gp3"
}

variable "data_volume_size" {
  description = "Data EBS Volume size (storage for synced content and TLS certs)"
  type        = number
  default     = 10
}

variable "imdsv2_enabled" {
  description = "Enable IMDSv2"
  type        = bool
  default     = false
}

variable "ebs_kms_key_id" {
  description = "CMK used for EBS Encryption"
  type        = string
  default     = null
}
