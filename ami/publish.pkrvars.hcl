# Publishing config for the public sheesh box AMI. NOT auto-loaded by Packer;
# pass it explicitly to opt into publishing:
#
#   packer build -var-file=publish.pkrvars.hcl .
#
# CI passes the equivalent values as env vars (see ../.github/workflows/build-ami.yml).
# These values are project policy (not account-specific), so they live in git.

# Copy the built AMI to these ADDITIONAL regions. Must NOT include the build
# region (aws_region) or Packer will try to copy an image onto itself.
# The project ships the box in us-east-1 (build region) + ap-southeast-1.
ami_regions = [
  "ap-southeast-1",
]

# Make the AMI (and its copies) public.
ami_groups = [
  "all",
]

# Optionally share with an AWS Organization instead of / in addition to public:
# aws organizations describe-organization --query Organization.Arn --output text
ami_org_arns = [
  # "arn:aws:organizations::<account-id>:organization/<org-id>",
]
