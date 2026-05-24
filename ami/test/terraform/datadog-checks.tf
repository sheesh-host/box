
resource "aws_s3_bucket" "datadog_agent_config" {
  bucket = "${local.name_prefix}-datadog-agent-config"
}

resource "aws_s3_bucket_ownership_controls" "datadog_agent_config" {
  bucket = aws_s3_bucket.datadog_agent_config.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

locals {
  datadog_checks = {
    http_check = {
      # these are stored on s3 and synced into the instance
      confd_files = {
        config   = "conf.d/datadog-http_check.toml"
        template = "templates/datadog-http_check.yaml.tmpl"
      }
      # this is stored in SSM Parameter store and dynamically read by confd
      # refer to https://github.com/DataDog/integrations-core/blob/master/http_check/datadog_checks/http_check/data/conf.yaml.example
      contents = {
        init_config = {}
        instances = [
          {
            name = "Handshakes APP"
            url  = "https://app.handshakes.com.sg"
          },
          {
            name = "Handshakes API"
            url  = "https://api.handshakes.com.sg"
          },
        ]
      }
    }
  }

  # flatten all confd_files for all datadog checks
  datadog_check_files = flatten([for check_name, check in local.datadog_checks :
    [for file_name, file_relative_path in check.confd_files : {
      check_name = check_name
      file_name  = file_name
      file_path  = "datadog-checks/${file_relative_path}"
    }]
  ])
}

resource "aws_s3_object" "datadog_checks" {
  for_each = { for o in local.datadog_check_files : "${o.check_name}_${o.file_name}" => o }

  bucket = aws_s3_bucket.datadog_agent_config.id
  key    = each.value.file_path
  source = each.value.file_path
  etag   = filemd5(each.value.file_path)
}

resource "aws_ssm_parameter" "datadog_checks_contents" {
  for_each       = local.datadog_checks
  name           = "/${local.name_prefix}/datadog/${each.key}/contents"
  description    = "${local.name_prefix} DataDog ${each.key} contents"
  type           = "String"
  tier           = "Standard"
  insecure_value = yamlencode(each.value.contents)
}
