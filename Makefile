###############################################################################
# kris — single Go binary for managing krisyotam.com content
#
# NOTE: builds are intentionally NOT run here automatically. The user runs
#       them explicitly. This Makefile is documentation of the build steps.
###############################################################################

BINARY      = kris
INSTALL_DIR = /usr/local/bin
GO_FILES    = $(shell find . -name '*.go' -not -path './vendor/*')

.PHONY: build install clean fmt vet test completions help

help:
	@echo "kris — make targets"
	@echo "  build        Build the binary into ./bin/$(BINARY)"
	@echo "  install      Install to $(INSTALL_DIR) (requires sudo)"
	@echo "  fmt          gofmt all sources"
	@echo "  vet          go vet"
	@echo "  test         run tests"
	@echo "  completions  regenerate fish/sh/mksh completions"
	@echo "  clean        remove ./bin"

build:
	go build -o bin/$(BINARY) ./cmd/kris

install: build
	install -m 755 bin/$(BINARY) $(INSTALL_DIR)/$(BINARY)

fmt:
	gofmt -w $(GO_FILES)

vet:
	go vet ./...

test:
	go test ./...

completions: build
	./bin/$(BINARY) completion fish > completions/kris.fish
	./bin/$(BINARY) completion bash > completions/kris.bash
	./bin/$(BINARY) completion zsh  > completions/kris.zsh

clean:
	rm -rf bin
