# sheesh box AMI (arm64)

A Packer build for the sheesh.host box: an Ubuntu 24.04 arm64 image that serves
a git-backed static site. It bundles three systemd services:

| Service  | Role |
|----------|------|
| **caddy**    | TLS termination (ACME/Let's Encrypt) and static file serving from the synced content directory. |
| **git-sync** | Polls the content repo's tracked branch and atomically updates the served worktree. |
| **confd**    | Renders each service's config from AWS SSM Parameter Store (60s poll) so config changes need no rebuild. |

Each service lives under `assets/<service>/` as a self-contained unit:
`init.sh` (boot-time wiring), its systemd `*.service`/`*.path` units, and a
`confd/` subtree (`conf.d/` manifests + `templates/`). Shared boot scripts
(`attach-ebs.sh`, `associate-address.sh`, `functions.sh`) come from
[`../shared`](../shared) and install to `/opt/sheesh/shared`.

## Build

Configure your account's build infra once (default VPC + a default public
subnet in your build region). The local file is git-ignored:

```sh
cp .auto.pkrvars.hcl.example .auto.pkrvars.hcl
# edit aws_region / vpc_id / subnet_id for your account
```

```sh
packer init .

# Private image in aws_region only (good for testing):
packer build .

# Public image, copied to ami_regions (what CI publishes):
packer build -var-file=publish.pkrvars.hcl .

# Validate without building:
packer validate -var vpc_id=vpc-xxxx -var subnet_id=subnet-xxxx .
```

CI builds and publishes the AMI on an `ami-v*` tag and regenerates the public
`amis.json` catalog the `sheesh` CLI consumes
(see [`../.github/workflows/build-ami.yml`](../.github/workflows/build-ami.yml)).
It builds in `us-east-1`, copies to `ap-southeast-1`, and makes both public.
AWS access uses GitHub OIDC (no stored keys) via the
`sheesh-box-ami-builder` IAM role; build infra comes from the repo variables
`AWS_REGION` / `PACKER_VPC_ID` / `PACKER_SUBNET_ID`.

## Runtime layout

- Content served from the git-sync data dir on the mounted EBS volume
  (`/var/lib/sheesh/git`).
- Caddy certs/storage under `/var/lib/sheesh/proxy`.
- Config sourced from SSM under `/<name_prefix>/...` (caddy data, content
  git-sync env + deploy key).
