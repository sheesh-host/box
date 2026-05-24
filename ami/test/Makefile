include ../../../scripts/common.mk

all: setup build-ami run-ami

setup: ## set up working directory by installing dependencies
	@(cd ${REPO_ROOT}/packer;packer init atlantis-arm64)
.PHONY: setup

clean: ## clean up
	@(cd terraform;terraform destroy)
	@-bash $(REPO_ROOT)/scripts/cleanup-ami.sh terraform/terraform.tfvars
	@rm -rf terraform/terraform.tfvars
	@rm -rf build.log
.PHONY: clean

build-ami: terraform/terraform.tfvars ## build ami and generate tfvars
.PHONY: build-ami

apply-ami: build-ami ## apply TF config for ami
	@(cd terraform;terraform init && terraform apply)
.PHONY: test-ami

e2e: ## run terratest e2e
	go test -v -timeout 45m

PACKER_ASSETS         := $(wildcard ../assets/*/*)
PACKER_SCRIPTS        := $(wildcard ../scripts/*.sh)
PACKER_SHARED_SCRIPTS := $(wildcard ../../shared/scripts/*.sh)
PACKER_CONFIG         := ../build.pkr.hcl ../.auto.pkrvars.hcl
terraform/terraform.tfvars: $(PACKER_ASSETS) $(PACKER_SCRIPTS) $(PACKER_SHARED_SCRIPTS)
	@(cd ${REPO_ROOT}/packer;packer build -debug -machine-readable -var 'pr=true' atlantis-arm64 | tee "atlantis-arm64/test/build.log")
	@bash $(REPO_ROOT)/scripts/gen-tfvars.sh terraform/terraform.tfvars
	@rm -rf build.log

help: ## display help for this makefile
	@fgrep -h "##" $(MAKEFILE_LIST) | fgrep -v fgrep | sed -e 's/\\$$//' | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
.PHONY: help
