# sheesh box — Terraform module

Deploys a single-node sheesh.host box: an ASG-of-1 running the
[sheesh AMI](../ami) behind a stable EIP, with a persistent EBS data volume and
a Route53 A record. The node is a stateless projection of the content git repo;
git-sync pulls the tracked branch and Caddy serves it over TLS.

Typically you don't write tfvars by hand — run [`sheesh init`](../cmd/sheesh) to
render `sheesh.auto.tfvars.json` (and an optional S3 backend), then:

```sh
terraform init
terraform apply
```

## Ops notes

Access the box shell via AWS Session Manager:

```sh
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names <asg_name> \
  --query "AutoScalingGroups[].Instances[].InstanceId" --output text
aws ssm start-session --target <instance_id>
```

Features:

- Public EC2 instance with a stable EIP (survives instance replacement)
- Optional scheduled ASG scale up/down (UTC-based)
- Persistent EBS data volume (attached + mounted by the instance via
  `attach-ebs.sh`), holding synced content and TLS certs

> [!WARNING]
> Scaling triggers are based on Coordinated Universal Time (UTC).

<!-- BEGIN_TF_DOCS -->
<!-- Run `make docs` (needs terraform-docs) to generate the inputs/outputs table. -->
<!-- END_TF_DOCS -->
