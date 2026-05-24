locals {
  volume_mount = "/var/lib/sheesh"

  # json data for gotemplate (confd renders the Caddyfile from this)
  # gotemplate fails on kebab case keys: bad character U+002D '-'
  caddy_data = {
    host        = "${var.hostname}.${var.dns_domain}"
    dataDir     = "${local.volume_mount}/proxy/"
    contentRoot = "${local.volume_mount}/git/content"
    testCert    = var.acme_staging
    email       = var.acme_email
  }
  arn_ssm_parameter_prefix = "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter"

  # written out-of-band (by `sheesh init`) into SSM as a SecureString; hardcoded
  # path in the AMI's content git-sync confd template.
  content_deploy_key_arn = "${local.arn_ssm_parameter_prefix}/${var.name_prefix}/content-deploy-key/contents"
}

resource "aws_ssm_parameter" "caddy_data" {
  name           = "/${var.name_prefix}/caddy/data"
  description    = "${var.name_prefix} caddy config"
  type           = "String"
  tier           = "Standard"
  insecure_value = jsonencode(local.caddy_data)
}

resource "aws_ssm_parameter" "content_env" {
  name        = "/${var.name_prefix}/content-env/contents"
  description = "${var.name_prefix} Environmentfile for the content git-sync"
  type        = "String"
  tier        = "Standard"
  insecure_value = templatefile("${path.module}/config/content.env.tpl", {
    github_org     = var.github_org
    content_repo   = var.content_repo
    content_branch = var.content_branch
    data_dir       = "${local.volume_mount}/git"
  })
}
