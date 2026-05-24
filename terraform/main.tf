data "aws_route53_zone" "domain" {
  name         = var.dns_domain
  private_zone = false
}

resource "aws_security_group" "node" {
  name        = "${var.name_prefix}-security-group"
  description = "${var.name_prefix} security group"
  vpc_id      = var.vpc_id

  # required for certbot
  ingress {
    description      = "HTTP from world"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "TLS from world"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    description      = "Default egress all"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "${var.name_prefix}-security-group"
  }
}

data "aws_subnet" "main" {
  id = var.subnet_id
}

resource "aws_eip" "node" {
  domain = "vpc"
}

resource "aws_ebs_volume" "data" {
  # Note: https://github.com/hashicorp/terraform/issues/22544
  count             = var.data_volume_prevent_destroy ? 1 : 0
  availability_zone = data.aws_subnet.main.availability_zone
  type              = var.data_volume_type
  size              = var.data_volume_size

  encrypted  = true
  kms_key_id = var.ebs_kms_key_id

  tags = {
    Name = "${var.name_prefix}-data"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ebs_volume" "ephemeral" {
  count             = var.data_volume_prevent_destroy ? 0 : 1
  availability_zone = data.aws_subnet.main.availability_zone
  type              = var.data_volume_type
  size              = var.data_volume_size

  encrypted  = true
  kms_key_id = var.ebs_kms_key_id

  tags = {
    Name = "${var.name_prefix}-data"
  }

  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_route53_record" "node" {
  zone_id = data.aws_route53_zone.domain.id
  name    = var.hostname
  ttl     = 80
  type    = "A"
  records = [aws_eip.node.public_ip]
}

locals {
  volume_data = var.data_volume_prevent_destroy ? aws_ebs_volume.data[0] : aws_ebs_volume.ephemeral[0]
}
data "cloudinit_config" "node" {
  gzip = false
  part {
    # https://cloudinit.readthedocs.io/en/latest/topics/format.html#user-data-script
    content_type = "text/x-shellscript"
    content = templatefile("${path.module}/config/cloud-init.sh.tpl", {
      name_prefix   = var.name_prefix
      ebs_volume_id = local.volume_data.id
      allocation_id = aws_eip.node.id
      volume_mount  = local.volume_mount
    })
  }
}

resource "aws_launch_template" "node" {
  name                                 = "${var.name_prefix}-node"
  vpc_security_group_ids               = [aws_security_group.node.id]
  image_id                             = var.ami_id
  user_data                            = data.cloudinit_config.node.rendered
  instance_type                        = var.instance_type
  instance_initiated_shutdown_behavior = "terminate"
  disable_api_stop                     = false
  disable_api_termination              = false

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      delete_on_termination = true
      volume_size           = var.root_volume_size
      volume_type           = var.root_volume_type
      encrypted             = true
      kms_key_id            = var.ebs_kms_key_id
    }
  }

  iam_instance_profile {
    name = aws_iam_instance_profile.node.name
  }

  placement {
    # match EBS Volume AZ
    availability_zone = data.aws_subnet.main.availability_zone
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "${var.name_prefix}-node"
    }
  }

  monitoring {
    enabled = true
  }

  dynamic "metadata_options" {
    for_each = var.imdsv2_enabled ? [1] : []
    content {
      http_endpoint               = "enabled"
      http_tokens                 = "required"
      http_put_response_hop_limit = 1
      instance_metadata_tags      = "enabled"
    }
  }
}
locals {
  asg_min = 0
  asg_max = 1
}

resource "aws_autoscaling_group" "node" {
  name_prefix         = var.name_prefix
  vpc_zone_identifier = [data.aws_subnet.main.id]
  desired_capacity    = 1
  health_check_type   = "EC2"
  min_size            = local.asg_min
  max_size            = local.asg_max

  dynamic "tag" {
    for_each = var.tags
    content {
      key                 = tag.key
      value               = tag.value.value
      propagate_at_launch = tag.value.propagate_at_launch
    }
  }

  launch_template {
    id      = aws_launch_template.node.id
    version = aws_launch_template.node.latest_version
  }

  instance_refresh {
    strategy = "Rolling"
  }

  lifecycle {
    ignore_changes = [
      desired_capacity,
    ]
  }
}

resource "aws_autoscaling_schedule" "scale_down" {
  scheduled_action_name  = "${var.name_prefix}-scale-down"
  min_size               = local.asg_min
  max_size               = local.asg_max
  desired_capacity       = 0
  recurrence             = "0 ${var.hour_to_scale_down} * * *"
  autoscaling_group_name = aws_autoscaling_group.node.name
  lifecycle {
    ignore_changes = [start_time]
  }
}

resource "aws_autoscaling_schedule" "scale_up" {
  scheduled_action_name = "${var.name_prefix}-scale-up"
  min_size              = local.asg_min
  max_size              = local.asg_max
  desired_capacity      = 1
  # UTC 23:00 SUN == SGT 07:00 MON
  # UTC 23:00 THU == SGT 07:00 FRI
  recurrence             = "0 ${var.hour_to_scale_up} * * SUN-THU"
  autoscaling_group_name = aws_autoscaling_group.node.name
  lifecycle {
    ignore_changes = [start_time]
  }
}
