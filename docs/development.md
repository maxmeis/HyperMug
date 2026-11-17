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

`make test-runtime` runs actual subprocess isolation/exit/timeout/cleanup checks and fake native-notification delivery and in-app JSON-editor model adapters, without requesting macOS notification permissions or launching HyperMug.

`make test-window` opens an isolated native window fixture on a logged-in Mac. It tests window reuse, resizing, raw JSON editing, Undo/Redo, Command-S, invalid saves and discard confirmation with a temporary file and no input engine or permission requests. It is intentionally excluded from headless CI. Optional `HYPERMUG_TEST_CAPTURE_DIRECTORY=/tmp/hypermug-ui-evidence make test-window` captures only the fixture window, using existing Screen Recording permission; it never requests that permission.

`make test` requires 100% executable-line coverage. `make compile-check` type-checks the app. `make test-release` checks release metadata and publication with temporary repositories. `make check-automation` and `make check-website` check repository automation and website assets. CI and Git hooks use these Makefile targets.

Run `make ci-tools` to install the locked Node tooling. Run `make hooks` to install Git hooks again if npm scripts were disabled. Commits follow [Conventional Commits](../CONTRIBUTING.md#commit-messages).

## CI scope and workflow dependencies

The required GitHub Actions check remains `ci`. Pull requests run CI; pushes run CI on `main` and the two managed `release-casks/stable` and `release-casks/canary` branches. This avoids running the same feature change twice on push and pull request. A branch without a pull request can be checked through manual CI dispatch.

An Ubuntu job examines the complete change range. Only README/CONTRIBUTING, `docs/`, website, skills, and the two existing channel casks qualify for Linux CI. Linux still runs layer rules, release/publication tests, shell syntax, CI-selection tests, automation tests, content checks and commit lint. App, branding, build, workflow, dependency and unknown changes run all checks on macOS, including Core coverage, native adapters, compilation and the ad-hoc bundle build. Manual runs and missing/invalid/empty change ranges also use full macOS checks. Failed selection fails the required check. Renames inspect both paths. Run `make test-ci` for the Git-history regression tests.

All workflow Actions are pinned to upstream commit SHAs. Dependabot proposes weekly Actions updates for review; it does not merge them automatically. Checkout credentials are not persisted. Job timeouts bound CI and release execution. Stable stays manually versioned with production approval, Canary stays automatic, and verified cask metadata continues publishing without a release PR. These changes do not grant tokens or change repository/environment protection.

The measured pre-change docs PR #27 used 212 seconds for PR CI and 267 seconds for duplicate push CI (479 macOS runner-seconds total). A pure cask update used 224 seconds. Removing the duplicate eliminates one macOS run per ordinary feature PR update; moving known content-only runs to Linux removes their native build work. Actual new runtimes must be measured from live workflows; these baseline numbers are not claimed savings or a latency guarantee.

## Issue-first planning

Plan work through GitHub issues with one of three types: **Feature**, **Bug**, or **Misc**. Use the matching `feature`, `bug`, or `misc` label and the corresponding issue form when available. Only issues authored by the verified repository owner, `maxmeis`, enter the actionable backlog and can authorize automated work. Outside issues and comments are welcome as public discussion and reports, but they do not automatically authorize triage work or implementation. No automatic triage or implementation is promised for external reports.

Public pull requests are welcome. For substantial changes, first check whether an owner-authored issue describes the work; if it does not, discuss it in an issue and let the owner decide whether to create backlog work. See [Contributing](../CONTRIBUTING.md).

The [file configuration/macOS/Swift audit](audits/file-config-macos-swift.md) records the requested skills, scope, findings and validation limits.
