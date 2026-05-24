GO ?= go
BIN := sheesh

.PHONY: build test race lint fmt tidy snapshot clean

build: ## build the sheesh CLI into ./bin
	$(GO) build -o bin/$(BIN) ./cmd/sheesh

test: ## run unit tests
	$(GO) test ./...

race: ## run unit tests with the race detector
	$(GO) test -race ./...

lint: ## run golangci-lint (needs a build >= the module go directive)
	golangci-lint run ./cmd/... ./pkg/...

fmt: ## format Go sources
	gofmt -w cmd pkg

tidy: ## tidy module dependencies
	$(GO) mod tidy

snapshot: ## build release artifacts locally without publishing
	goreleaser build --snapshot --clean

clean:
	rm -rf bin dist
