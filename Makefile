SHELL=/bin/bash -o pipefail

REGISTRY ?= pranganmajumder
BIN      := predis-init
IMAGE    := $(REGISTRY)/$(BIN)
#TAG      := $(shell git describe --exact-match --abbrev=0 2>/dev/null || echo "")
TAG      := 0.0.3


.PHONY: push
push: container
	docker push $(IMAGE):$(TAG)

.PHONY: container
container:
	docker build -t $(IMAGE):$(TAG) .