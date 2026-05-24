output "role_arn" {
  value = aws_iam_role.node.arn
}

output "asg_name" {
  value = aws_autoscaling_group.node.name
}
