# sheesh box e2e tests

[terratest](https://terratest.gruntwork.io/) end-to-end test for the box: it
builds the [sheesh AMI](../) with Packer, deploys it with the
[terraform module](../../terraform), and asserts the box serves its synced
content over TLS.

This is a **separate Go module** (`github.com/sheesh-host/box/ami/test`) so its
terratest/AWS-SDK dependencies stay out of the CLI module's graph.

## What it does

1. **build_ami** — `packer build` the AMI in the account's default VPC.
2. **deploy_terraform** — apply [`terraform/`](terraform) (the module under test
   against the default VPC, Let's Encrypt **staging** certs, a destroyable EBS
   volume), seeding the content git-sync deploy key into SSM.
3. **validate** — wait for the ASG/SSM, dump `confd`/`caddy`/`content` logs, and
   assert `https://<hostname>.<dns_domain>/` returns `200`.
4. Cleanup destroys the stack and deregisters the AMI.

## Running

Requires AWS credentials for a test account **and** these inputs (the test
`Skip`s without them, so CI stays green):

| Env var | Meaning |
|---------|---------|
| `SHEESH_TEST_DNS_DOMAIN` | a Route53 zone in the test account (e.g. `example.com`) |
| `SHEESH_TEST_CONTENT_REPO` | content repo to serve, `org/repo` |
| `SHEESH_TEST_DEPLOY_KEY` | PEM private deploy key with read access to that repo |
| `SHEESH_TEST_AWS_REGION` | optional, default `ap-southeast-1` |
| `SHEESH_TEST_CONTENT_BRANCH` | optional, default `main` |

```sh
export SHEESH_TEST_DNS_DOMAIN=example.com
export SHEESH_TEST_CONTENT_REPO=my-org/site
export SHEESH_TEST_DEPLOY_KEY="$(cat ./deploy_key)"
make e2e
```

Iterate locally with terratest test stages by skipping completed stages, e.g.
`SKIP_build_ami=true SKIP_cleanup_ami=true SKIP_cleanup_terraform=true make e2e`
(see [iterating locally using test stages](https://terratest.gruntwork.io/docs/testing-best-practices/iterating-locally-using-test-stages/)).
