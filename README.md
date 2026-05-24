# box

> A single-node [sheesh.host](https://sheesh.host) instance, backed by git.

A small AWS box (built with [Packer](https://www.packer.io/)) that runs
[Caddy](https://caddyserver.com/) and [git-sync](https://github.com/kubernetes/git-sync):
push to a git repository and the content is served immediately over TLS,
optionally behind auth. Git is the source of truth and the audit log; the box is
a disposable projection of it. See [architecture.md](architecture.md).

## Layout

| Path | What |
|------|------|
| [`cmd/sheesh`](cmd/sheesh) | the `sheesh` bootstrap CLI (this Go module: `github.com/sheesh-host/box`) |
| [`pkg/`](pkg) | reusable libraries shared by the CLI (and a future `cmd/sheesh-server`) |
| [`ami/`](ami) | Packer build for the box AMI (Caddy + git-sync + confd) |
| [`terraform/`](terraform) | single-node module (ASG + EIP + EBS + Route53) |
| [`shared/`](shared) | boot scripts baked into the AMI (`/opt/sheesh/shared`) |

## Prerequisites

- An AWS account with permissions for EC2, EBS, security groups, IAM roles,
  SSM Parameter Store, and (for private content) repo deploy keys.
- A git repository to serve (public or private).
- [`terraform`](https://www.terraform.io/downloads) to deploy.

## Usage

Install the `sheesh` CLI from [releases](https://github.com/sheesh-host/box/releases),
then bootstrap a box:

```sh
# Interactive: prompts for anything not passed as a flag.
sheesh init

# Non-interactive: everything from flags.
sheesh init --non-interactive \
  --name demo --region ap-southeast-1 \
  --vpc-id vpc-xxxx --subnet-id subnet-xxxx \
  --domain example.com --hostname docs \
  --github-org sheesh-host --content-repo site \
  --acme-email ops@example.com
```

`sheesh init` resolves the latest AMI from the public catalog
(`https://sheesh.host/amis.json`), renders `terraform/sheesh.auto.tfvars.json`,
optionally writes an S3 backend (`--backend-bucket`), and can mint a read-only
ed25519 deploy key for a private content repo (`--with-deploy-key`). Then:

```sh
cd terraform && terraform init && terraform apply
```

## Development

```sh
make build   # build ./bin/sheesh
make test    # go test ./...
make lint    # golangci-lint
```
