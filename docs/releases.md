# Release process

HyperMug has one Production release workflow, `.github/workflows/release.yml`. Source pushes to protected `main` automatically test the exact pushed commit, select the next patch version, create its immutable `vX.Y.Z` tag, build and sign the app with Developer ID, notarize and staple it, publish a GitHub Release, and commit `Casks/hypermug.rb` directly to `main`. There are no release PRs or manual version/tag inputs.

## Production publication

App sources, branding, build helpers, the Makefile and release workflow trigger releases. Documentation, website, skills and generated cask-only changes do not. Publication runs are serialized without canceling a running release. The migration baseline is the existing `v0.3.0` release. The new workflow allocates `v0.3.N` from its immutable GitHub run number `N` (first run: `v0.3.1`). Retries reuse that number and require its tag to point to the same source SHA. Failed runs can leave version gaps. A queued older run keeps its lower version even if it executes later, and cannot move the latest release or cask backward.

The release job checks out the tested push SHA and uses the repository's `GITHUB_TOKEN` with Contents write to publish tags and releases. It imports the Developer ID certificate into a temporary keychain, builds the Production bundle, requires Apple's notarization result to be Accepted, staples the app and verifies its signature and Gatekeeper assessment. It then packages the final stapled app as `HyperMug-X.Y.Z.zip`. Temporary signing credentials and keychain state are cleaned up on exit.

The publisher creates a draft with its artifact before publishing. Published tags and artifact bytes are never replaced. The Homebrew cask version, URL and SHA-256 refer to the release archive. Retrying a publication reuses existing published bytes. The cask commit changes only `Casks/hypermug.rb`, fetches current `main` to preserve intervening source changes, and never force-pushes. An older retry cannot move the cask backward.

Homebrew lives in this repository; no external tap, release service, GitHub App, Sparkle feed or update key is required. The publisher supports a repository-scoped SSH deploy key for protected-main cask writes; it uses `GITHUB_TOKEN` for cask writes when the branch permits that token. A token-authenticated push does not trigger another push workflow. An SSH push runs ordinary CI, while cask-only updates are excluded from release paths to prevent another release. Production updates use `brew upgrade --cask maxmeis/hypermug/hypermug`.

## Repository configuration

Source changes should merge through the protected `main` branch with required CODEOWNERS review. The workflow needs these separate publishing prerequisites:

- The `production` environment must permit `main` without a required reviewer or wait timer for fully automatic releases. Keep its deployment branch policy restricted to `main`.
- The publisher must be allowed to update the generated cask directly on `main`. `contents: write` does not bypass required pull requests or status checks. Under the current rules, configure a repository-scoped write deploy key and save its private key as the Production environment secret `HOMEBREW_SSH_PRIVATE_KEY`. The key needs an explicit PR/status-check ruleset exception; keep force-push and deletion protection in a separate ruleset without that bypass. The workflow itself does not weaken repository rules. Without a deploy key, the publisher uses `GITHUB_TOKEN` and the branch must permit that token's direct write.
- GitHub Actions must be allowed to create releases/tags with Contents write. Keep source review, force-push and deletion protections.

Before merging this migration, inspect both branch protection and rulesets: their rules apply together. A CODEOWNERS file alone does not grant CI a direct-push exception. Existing production approval and publication rules must be updated before claiming this pipeline is fully automatic.

## Production credentials

Keep Apple credentials in the `production` environment, accessible only to the release job. No credential is needed for local development or PR tests.

| Type | Name | Purpose |
| --- | --- | --- |
| Secret | `DEVELOPER_ID_P12_BASE64` | Base64-encoded Developer ID certificate and private key |
| Secret | `DEVELOPER_ID_P12_PASSWORD` | Export password for the certificate |
| Secret | `APP_STORE_CONNECT_PRIVATE_KEY` | App Store Connect API private key for notarization |
| Secret | `HOMEBREW_SSH_PRIVATE_KEY` | Repository-scoped cask publishing key when required by main branch rules |
| Variable | `SIGN_ID` | Full Developer ID Application signing identity |
| Variable | `APPLE_TEAM_ID` | Apple team identifier |
| Variable | `APP_STORE_CONNECT_KEY_ID` | Notarization API key identifier |
| Variable | `APP_STORE_CONNECT_ISSUER_ID` | Notarization API issuer identifier |

Retire old release-bot, external-tap and Sparkle credentials only after dependent projects have migrated and a real production publication plus Homebrew update has succeeded. Existing historical releases remain unchanged.

## Validation

`make test-release` exercises version selection, publication retries and signing/notarization error handling using isolated fixtures. `make check` also runs Core coverage, native subprocess checks, compilation, workflow helper and content checks. These local checks do not prove Developer ID credentials, Apple's notarization service, protected-branch publication or a clean-Mac install; verify those through an actual production workflow before announcing the migration complete.
