# Local build inputs for `packer build`. Replace with your own build VPC/subnet.
# CI passes these via PKR_VAR_vpc_id / PKR_VAR_subnet_id instead (see
# .github/workflows/build-ami.yml).
vpc_id        = "vpc-REPLACE_ME"
subnet_id     = "subnet-REPLACE_ME"
instance_type = "t4g.large"
