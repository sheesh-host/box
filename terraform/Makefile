TF ?= terraform

.PHONY: init validate fmt plan apply docs

init: ## terraform init
	$(TF) init

validate: ## fmt check + validate without a backend
	$(TF) fmt -check -recursive
	$(TF) init -backend=false
	$(TF) validate

fmt: ## format terraform files
	$(TF) fmt -recursive

plan: ## terraform plan
	$(TF) plan

apply: ## terraform apply
	$(TF) apply

docs: ## regenerate the README inputs/outputs table (needs terraform-docs)
	terraform-docs markdown table --output-file README.md --output-mode inject .
