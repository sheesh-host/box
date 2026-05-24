# Atlantis e2e tests

This uses [terratest](https://terratest.gruntwork.io/) to do e2e tests of the
Atlantis AMI built.

## One time set up

> `go.sum` committed to repo, no need to re-run

```sh
cd test
go mod init atlantis-arm64
go mod tidy
```

## Running tests

```sh
make e2e
```

## Manually testing

Make targets without terratest.

```sh
$ make help
help                           display help for this makefile
setup                          set up working directory by installing dependencies
build-ami                      build ami and generate tfvars
apply-ami                      apply TF config for ami
e2e                            run terratest e2e
clean                          clean up
...
```

These make targets allow you to build AMI and iterate on TF config.

> [!NOTE]
> Ideally follow [iterating locally using test stages](https://terratest.gruntwork.io/docs/testing-best-practices/iterating-locally-using-test-stages/) from terratest docs.
