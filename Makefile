SHELL := /bin/bash
.DEFAULT_GOAL := help

.PHONY: help dev check-content check-automation check-website triage setup install-tools ci-tools hooks signing build build-production run restart test test-ci test-release test-runtime test-window check-shell check-layers compile-check check release publish validate-release sparkle-keys lint-commit lint-commits clean

help:
	@printf '%s\n' \
	  'make setup             Install development tools and the local signing identity' \
	  'make run               Build Dev, stop other instances, and open Doctor' \
	  'make restart           Restart the existing Dev build and open Doctor' \
	  'make build             Build HyperMug Dev without launching it' \
	  'make build-production  Build with the production identity locally' \
	  'make check             Run all checks' \
	  'make test              Run Core tests with the coverage gate' \
	  'make test-release      Run release integration tests' \
	  'make test-runtime      Check shell supervision, notifications and config editing' \
	  'make test-window       Open an isolated native UI test window (no input capture)' \
	  'make compile-check     Type-check the app' \
	  'make signing           Create the persistent local signing identity' \
	  'make sparkle-keys      Open the Sparkle signing key tool' \
	  'make release           Build and notarize with release environment variables' \
	  'make publish           Publish with release environment variables' \
	  'make clean             Remove generated build files'

setup: install-tools signing

install-tools:
	npm install

ci-tools:
	npm ci

hooks:
	npm run prepare

signing:
	./helpers/create-signing-cert.sh

build:
	./helpers/build.sh

build-production:
	$(MAKE) build APP_VARIANT=production REQUIRE_SIGNING=0

run:
	$(MAKE) build APP_VARIANT=dev REQUIRE_SIGNING=0
	./helpers/run-local.sh

restart:
	./helpers/run-local.sh

test:
	./helpers/test.sh

test-runtime:
	./helpers/test-runtime.sh

test-window:
	./helpers/test-window.sh

test-release:
	GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s helpers -p 'test_release*.py'

test-ci:
	GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s helpers -p 'test_ci*.py'

check-shell:
	@for helper in helpers/*.sh; do bash -n "$$helper" || exit $$?; done
	@for hook in .husky/commit-msg .husky/pre-commit .husky/pre-push helpers/hook-lib.sh; do sh -n "$$hook" || exit $$?; done

check-layers:
	./helpers/check-layers.sh

compile-check:
	./helpers/compile-check.sh

check: check-layers check-shell test-ci test-release test compile-check check-automation check-website test-runtime

release:
	+./helpers/release.sh

publish:
	./helpers/publish_release.sh

validate-release:
	python3 helpers/release_metadata.py validate --channel "$${CHANNEL:?}" --version "$${VERSION:?}" \
	  --actor "$${GITHUB_ACTOR:?}" --triggering-actor "$${GITHUB_TRIGGERING_ACTOR:?}" \
	  --ref "$${GITHUB_REF:?}" --sha "$${GITHUB_SHA:?}" --source-repo "$${SOURCE_REPOSITORY:?}" \
	  --releases-repo "$${RELEASES_REPOSITORY:?}" --tap-repo "$${TAP_REPOSITORY:?}"

sparkle-keys:
	. helpers/sparkle.sh; sparkle_prepare; "$$SPARKLE_ROOT/bin/generate_keys"

lint-commit:
	npx --no-install commitlint --edit "$${COMMIT_MSG_FILE:?}"

lint-commits:
	npx --no-install commitlint --from "$${FROM:?}" --to "$${TO:?}" --verbose

clean:
	rm -rf build

# Repository automation uses the same command entry point as the app.
dev: build

check-content:
	python3 helpers/automation/check-content.py

check-automation:
	node --check helpers/automation/triage-issues.mjs
	node --test helpers/automation/triage-issues.test.mjs

check-website: check-content
	node --check Source/Website/script.js

triage:
	node helpers/automation/triage-issues.mjs
