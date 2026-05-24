.PHONY: e2e vet fmt clean help

e2e: ## run the terratest e2e (needs AWS creds + SHEESH_TEST_* env, see README)
	go test -v -timeout 60m ./...

vet: ## vet the test module
	go vet ./...

fmt: ## format the test module
	gofmt -w .

clean: ## remove terratest scratch + local terraform state
	rm -rf terraform/.test-data terraform/.terraform terraform/*.tfstate*

help: ## display help for this makefile
	@fgrep -h "##" $(MAKEFILE_LIST) | fgrep -v fgrep | sed -e 's/\\$$//' | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-22s\033[0m %s\n", $$1, $$2}'
