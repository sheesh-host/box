# Node role
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

resource "aws_iam_role" "node" {
  name               = "${var.name_prefix}-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.node.id
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "additional_attached_policy_arns" {
  for_each   = toset(var.additional_attached_policy_arns)
  role       = aws_iam_role.node.id
  policy_arn = each.value
}

# inline parameter store
# https://docs.aws.amazon.com/systems-manager/latest/userguide/sysman-paramstore-access.html
data "aws_iam_policy_document" "node_parameterstore" {
  statement {
    actions = [
      "ssm:DescribeParameters"
    ]
    effect    = "Allow"
    resources = ["*"]
  }
  statement {
    # note: this overlaps with
    # arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore includes:
    # "Resource": "*"
    # "Actions": [
    #       "ssm:GetParameter",
    #       "ssm:GetParameters"
    # ]
    actions = [
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
    ]
    effect = "Allow"
    resources = [
      aws_ssm_parameter.caddy_data.arn,
      aws_ssm_parameter.content_env.arn,
      local.content_deploy_key_arn,
    ]
  }
}

resource "aws_iam_role_policy" "node_parameterstore" {
  name   = "${var.name_prefix}-parameterstore-policy"
  policy = data.aws_iam_policy_document.node_parameterstore.json
  role   = aws_iam_role.node.name
}

# inline ebs attach
data "aws_iam_policy_document" "node_ebs_attach" {
  statement {
    actions = [
      "ec2:DescribeVolumes",
      "ec2:DescribeInstances",
    ]
    effect = "Allow"
    resources = [
      "*"
    ]
  }
  statement {
    actions = [
      "ec2:AttachVolume",
      "ec2:DetachVolume",
    ]
    effect = "Allow"
    resources = [
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/*",
      local.volume_data.arn,
    ]
  }
}

resource "aws_iam_role_policy" "node_ebs_attach" {
  name   = "${var.name_prefix}-ebs-attach-policy"
  policy = data.aws_iam_policy_document.node_ebs_attach.json
  role   = aws_iam_role.node.name
}

# inline eip associate
data "aws_iam_policy_document" "node_eip_associate" {
  statement {
    actions = [
      "ec2:DescribeAddresses",
    ]
    effect = "Allow"
    resources = [
      "*"
    ]
  }
  statement {
    actions = [
      "ec2:AssociateAddress",
    ]
    effect = "Allow"
    # https://docs.aws.amazon.com/service-authorization/latest/reference/list_amazonec2.html
    resources = [
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/*",
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:elastic-ip/${aws_eip.node.allocation_id}",
    ]
  }
}

resource "aws_iam_role_policy" "node_eip_associate" {
  name   = "${var.name_prefix}-eip-associate-policy"
  policy = data.aws_iam_policy_document.node_eip_associate.json
  role   = aws_iam_role.node.name
}

# inline additional
data "aws_iam_policy_document" "additional_inline_policies" {
  for_each = { for k, v in var.additional_inline_policies :
    k => v
    if length(v.policy) > 0
  }

  dynamic "statement" {
    for_each = each.value.policy
    content {
      sid           = statement.key
      effect        = statement.value.effect
      actions       = statement.value.actions
      resources     = statement.value.resources
      not_resources = statement.value.not_resources

      dynamic "condition" {
        for_each = statement.value.conditions
        content {
          test     = condition.value.test
          variable = condition.value.variable
          values   = condition.value.values
        }
      }
    }
  }
}

resource "aws_iam_role_policy" "additional_inline_policies" {
  for_each = { for k, v in var.additional_inline_policies :
    k => v
    if length(v.policy) > 0
  }
  name   = "${var.name_prefix}-${each.key}-policy"
  policy = data.aws_iam_policy_document.additional_inline_policies[each.key].json
  role   = aws_iam_role.node.name
}

resource "aws_iam_instance_profile" "node" {
  name = var.name_prefix
  role = aws_iam_role.node.name
}
