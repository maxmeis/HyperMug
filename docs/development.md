# Development

The Swift app, tests, and build tooling are in `Source/HyperMug/`. Repository-wide commit hooks and commit-message linting remain at the repository root and use the existing npm lockfile.

## Build and run

On macOS with Xcode Command Line Tools installed, from the repository root:

```sh
make build  # ad-hoc signed; does not launch
make test   # Core tests and coverage
make run    # explicitly build and launch
```

`make check` runs tests and builds; `make clean` removes generated app/test output while keeping the dependency cache. For layer and compile checks, run `./Source/HyperMug/scripts/check-layers.sh` and `./Source/HyperMug/scripts/compile-check.sh`. Build products go under `Source/HyperMug/build/`. `make build` pins `SIGN_ID=-` and disables the updater, Developer ID signing, and notarization; it needs no Apple account. To keep Accessibility and Input Monitoring grants across rebuilds, create the optional local signing identity once:

```sh
cd Source/HyperMug
./scripts/create-signing-cert.sh
```

This creates `HyperMug Local Signing` in the login keychain and needs no administrator access. To use it, run `SIGN_ID='HyperMug Local Signing' ./Source/HyperMug/build.sh` directly; `make build` intentionally remains ad-hoc. Without a persistent identity, macOS can request permissions again after each rebuild. Release CI uses the same builder with Developer ID signing, hardened runtime, and notarization.

## Architecture and checks

The layer rules are enforced by `Source/HyperMug/scripts/check-layers.sh`:

- `Sources/Core`: pure logic with OS services supplied through injected interfaces.
- `Sources/Platform`: operating-system adapters; may depend on Core, not App.
- `Sources/App`: AppKit UI and composition root; may depend on Platform and Core.
- `Tests`: test Core only.

Core tests must maintain 100% executable-line coverage. The compile check builds Core and type-checks Platform and App. Run the layer check, tests, compile check, and release metadata checks before opening a pull request. CI runs these checks on macOS.

Root Node tooling is for Git hooks and commitlint only. Run `npm ci` from the repository root to install it; do not use package scripts as the Swift build or test entry point. Commits follow [Conventional Commits](../CONTRIBUTING.md#commit-messages).

## Issue-first planning

Plan work through GitHub issues with one of three types: **Feature**, **Bug**, or **Misc**. Use the matching `feature`, `bug`, or `misc` label and the corresponding issue form when available. Only issues authored by the verified repository owner, `maxmeis`, enter the actionable backlog and can authorize automated work. Outside issues and comments are welcome as public discussion and reports, but they do not automatically authorize triage work or implementation. No automatic triage or implementation is promised for external reports.

Public pull requests are welcome. For substantial changes, first check whether an owner-authored issue describes the work; if it does not, discuss it in an issue and let the owner decide whether to create backlog work. See [Contributing](../CONTRIBUTING.md).
