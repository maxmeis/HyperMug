# Development

App source and Core tests live in `Source/HyperMug/`. Build and automation helpers live in `helpers/`. Use the root Makefile for project commands.

## Build and run

On macOS with Xcode Command Line Tools installed:

```sh
make setup     # install development tools and the local signing identity
make build     # build HyperMug Dev without launching it
make run       # build Dev, stop other instances, and open Doctor
make restart   # restart the existing Dev build
make check     # run all checks
```

Run `make help` for the command list. Build products use the root `build/` directory. Set `BUILD_ROOT=/path/to/disposable-output` to build isolated bundles without replacing your running Dev app. The builder generates the variant’s schema into `Contents/Resources` before signing. `make clean` removes generated files.

Local builds use **HyperMug Dev** (`com.maxmeis.hypermug.dev`). Dev uses `~/.config/hypermug-dev.json` and `~/Library/Logs/HyperMug Dev/`. Production keeps its own name, bundle ID, permissions, settings, and logs. The local launcher copies production settings once, disables login launch and updates in that copy, and stops both app variants before launching Dev. If AeroSpace is available, it brings Doctor to the current workspace.

Run `make signing` to create `HyperMug Local Signing` in the login keychain. This needs no administrator access. The first build can ask you to allow codesign to use the key. Choose Always Allow. Builds stop if the signing identity is missing. Disposable CI builds can use `SIGN_ID=- ALLOW_ADHOC_SIGNING=1 make build`. These builds can lose permission grants when their signature changes.

Use `make build-production` for a local build with the production identity. Release CI uses `make release` with Developer ID signing and notarization. Release builds always use the production identity.

## Architecture and checks

The layer rules use `make check-layers`:

- `Source/HyperMug/Sources/Core`: pure logic with injected OS services.
- `Source/HyperMug/Sources/Platform`: OS adapters; may depend on Core, not App.
- `Source/HyperMug/Sources/App`: native UI and composition root.
- `Source/HyperMug/Tests`: Core tests.

`make test-runtime` runs actual subprocess isolation/exit/timeout/cleanup checks and a fake native-notification delivery adapter, without requesting macOS notification permissions or launching HyperMug.

`make test` requires 100% executable-line coverage. `make compile-check` type-checks the app. `make test-release` checks release metadata and publication with temporary repositories. `make check-automation` and `make check-website` check repository automation and website assets. CI and Git hooks use these Makefile targets.

Run `make ci-tools` to install the locked Node tooling. Run `make hooks` to install Git hooks again if npm scripts were disabled. Commits follow [Conventional Commits](../CONTRIBUTING.md#commit-messages).

## Issue-first planning

Plan work through GitHub issues with one of three types: **Feature**, **Bug**, or **Misc**. Use the matching `feature`, `bug`, or `misc` label and the corresponding issue form when available. Only issues authored by the verified repository owner, `maxmeis`, enter the actionable backlog and can authorize automated work. Outside issues and comments are welcome as public discussion and reports, but they do not automatically authorize triage work or implementation. No automatic triage or implementation is promised for external reports.

Public pull requests are welcome. For substantial changes, first check whether an owner-authored issue describes the work; if it does not, discuss it in an issue and let the owner decide whether to create backlog work. See [Contributing](../CONTRIBUTING.md).

The [file configuration/macOS/Swift audit](audits/file-config-macos-swift.md) records the requested skills, scope, findings and validation limits.
