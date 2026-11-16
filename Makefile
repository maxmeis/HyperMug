.DEFAULT_GOAL := help

.PHONY: help build dev run test check clean

help:
	@printf '%s\n' \
	  'make build  Build the app with ad-hoc signing and updates disabled' \
	  'make dev    Alias for build' \
	  'make run    Build, then explicitly launch the app' \
	  'make test   Run Core tests and coverage gate' \
	  'make check  Run tests and build the app' \
	  'make clean  Remove generated app, core and test outputs (keep dependency cache)'

build:
	@./Source/HyperMug/scripts/dev.sh

dev: build

run: build
	@open ./Source/HyperMug/build/HyperMug.app

test:
	@./Source/HyperMug/scripts/test.sh

check: test build

clean:
	@rm -rf -- ./Source/HyperMug/build/HyperMug.app ./Source/HyperMug/build/core ./Source/HyperMug/build/test
