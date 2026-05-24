# Optional publishing targets for the built AMI. Leave empty to keep the image
# private to the building account.
ami_regions = [
  # "ap-southeast-1",
]
ami_org_arns = [
  # Share with an AWS Organization, e.g.:
  # aws organizations describe-organization --query Organization.Arn --output text
  # "arn:aws:organizations::<account-id>:organization/<org-id>",
]
