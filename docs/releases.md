# Release process

HyperMug has one Production release workflow, `.github/workflows/release.yml`. Source pushes to protected `main` automatically test the exact pushed commit, select the next patch version, create its immutable `vX.Y.Z` tag, build and sign the app with Developer ID, notarize and staple it, publish a GitHub Release, commit the signed Sparkle feed `appcast-stable.xml` to the `updates` branch, and commit `Casks/hypermug.rb` directly to `main`. There are no release PRs or manual version/tag inputs.

## Production publication

App sources, branding, build helpers, the Makefile and release workflow trigger releases. Documentation, website, skills and generated cask-only changes do not. Publication runs are serialized without canceling a running release. The migration baseline is the existing `v0.3.0` release. The new workflow allocates `v0.3.N` from its immutable GitHub run number `N` (first run: `v0.3.1`). Retries reuse that number and require its tag to point to the same source SHA. Failed runs can leave version gaps. A queued older run keeps its lower version even if it executes later, and cannot move the latest release or cask backward.

The release job checks out the tested push SHA and uses the repository's `GITHUB_TOKEN` with Contents write to publish tags and releases. It imports the Developer ID certificate into a temporary keychain, builds the Production bundle, requires Apple's notarization result to be Accepted, staples the app and verifies its signature and Gatekeeper assessment. It then packages the final stapled app as `HyperMug-X.Y.Z.zip`. Temporary signing credentials and keychain state are cleaned up on exit.

The publisher creates a draft with its artifact before publishing. Published tags and artifact bytes are never replaced. The Homebrew cask version, URL and SHA-256 refer to the release archive. Retrying a publication reuses existing published bytes. The cask commit changes only `Casks/hypermug.rb`, fetches current `main` to preserve intervening source changes, and never force-pushes. An older retry cannot move the cask backward.

## In-app updates

Production bundles embed Sparkle 2. `helpers/sparkle.sh` downloads one pinned Sparkle release and refuses it unless its SHA-256 matches. The build copies `Sparkle.framework` with `ditto` so its symlinks survive, then re-signs its nested `Installer.xpc`, `Downloader.xpc`, `Autoupdate` and `Updater.app`, and then the framework, from the inside out, with the app's identity and, for releases, Developer ID with hardened runtime and a secure timestamp, before notarization. Release checks fail if any of those parts has the wrong team, no hardened runtime, no timestamp, or a broken framework symlink, both before notarization and again in the downloaded ZIP.

The Info.plist template carries `SUPublicEDKey`, `SUEnableAutomaticChecks`, `SUScheduledCheckInterval` (86400 seconds, so one check a day) and `SUVerifyUpdateBeforeExtraction`. Only the Production variant gets `SUFeedURL`, `https://raw.githubusercontent.com/maxmeis/hypermug/updates/appcast-stable.xml`; CI asserts that Dev builds have no feed. The `autoUpdate` setting turns scheduled checks on or off.

After the publisher downloads and verifies the published ZIP, `sign_update` signs those exact bytes with the `SPARKLE_ED_PRIVATE_KEY` environment secret. The key goes to `sign_update` on standard input and is never printed. `helpers/release_metadata.py appcast` then checks that the signature verifies with the `SUPublicEDKey` inside that ZIP, and writes a one-item feed: `sparkle:version` is the bundle's `CFBundleVersion`, plus `sparkle:shortVersionString`, the enclosure length, `sparkle:edSignature` and the release URL. If the secret is missing, the publisher fails before it touches the release. If the key does not match the app, the release stays a draft. The feed commit uses the same deploy key and GitHub SSH known-hosts setup as the cask commit, retries on races, and never force-pushes. A rerun of the same version is a no-op, and a feed that already lists a newer `sparkle:version` is left alone, so the feed never moves backward.

The update key was rotated for the first release after 0.3.1 because the original private key was lost. HyperMug 0.3.0 checked downloads against the old key before extracting them, so it cannot accept updates signed with the new key; its update attempts fail with a signature error. 0.3.1 has no updater. Users of either version run `brew upgrade --cask maxmeis/hypermug/hypermug` once. The new key also lives in the release maintainer's login keychain under the Sparkle account `hypermug-production`; export it with `generate_keys --account hypermug-production -x <file>` only into a private temporary file.

## Homebrew

Homebrew lives in this repository; no external tap, release service or GitHub App is required. The publisher supports a repository-scoped SSH deploy key for protected-main cask writes; it uses `GITHUB_TOKEN` for cask writes when the branch permits that token. A token-authenticated push does not trigger another push workflow. An SSH push runs ordinary CI, while cask-only updates are excluded from release paths to prevent another release. The cask declares `auto_updates true` because the app updates itself.

## Repository configuration

Production is active on protected `main`: the `production` environment is restricted to `main` with no required reviewers or wait timer, so source pushes release automatically. Source pull requests retain required CODEOWNERS review. The repository-scoped SSH deploy key is stored as the `production` environment secret `HOMEBREW_SSH_PRIVATE_KEY`; its ruleset exception permits the generated cask commit to bypass pull-request and required-check rules. Force-push and deletion protections are separate and have no deploy-key bypass. Actions uses `GITHUB_TOKEN` with Contents write for tags and releases.

Dependabot PRs, major bumps included, are queued for squash auto-merge by `.github/workflows/dependabot-automerge.yml` and merge once the required `ci` check passes. The merge uses `GITHUB_TOKEN`, so it starts no `push` workflows. A bump to the release or website workflow therefore neither releases nor redeploys. The updated actions first run on the next push that touches those workflows' paths. The workflow approves the PR itself, but only after `dependabot/fetch-metadata` verifies that every commit is a signed Dependabot commit. The owner-review ruleset therefore requires one approval rather than a CODEOWNERS approval; only the owner and this workflow can approve.

For a new repository using this workflow, restrict the `production` environment to `main` and leave reviewers and wait timers unset. Install a repository-scoped write deploy key and save its private key as `HOMEBREW_SSH_PRIVATE_KEY` in that environment. Add a narrow PR and required-check ruleset bypass for that key, while keeping source CODEOWNERS review and force-push/deletion protections in rulesets without the bypass. Inspect all applicable branch protections and rulesets together: `contents: write` and CODEOWNERS alone do not grant direct-push permission. Alternatively, omit the deploy key only when the repository's rules explicitly allow the workflow token to update the cask directly.

## Production credentials

Keep Apple credentials in the `production` environment, accessible only to the release job. No credential is needed for local development or PR tests.

| Type | Name | Purpose |
| --- | --- | --- |
| Secret | `DEVELOPER_ID_P12_BASE64` | Base64-encoded Developer ID certificate and private key |
| Secret | `DEVELOPER_ID_P12_PASSWORD` | Export password for the certificate |
| Secret | `APP_STORE_CONNECT_PRIVATE_KEY` | App Store Connect API private key for notarization |
| Secret | `HOMEBREW_SSH_PRIVATE_KEY` | Repository-scoped key for the cask and appcast commits when branch rules require it |
| Secret | `SPARKLE_ED_PRIVATE_KEY` | Sparkle EdDSA private key (base64 seed) that signs the appcast; must match `SUPublicEDKey` in `Source/HyperMug/Info.plist` |
| Variable | `SIGN_ID` | Full Developer ID Application signing identity |
| Variable | `APPLE_TEAM_ID` | Apple team identifier |
| Variable | `APP_STORE_CONNECT_KEY_ID` | Notarization API key identifier |
| Variable | `APP_STORE_CONNECT_ISSUER_ID` | Notarization API issuer identifier |

The first migrated production release, `v0.3.1`, has been published and its cask update verified. Retire old release-bot and external-tap credentials only after every dependent project has completed a real production publication and Homebrew update. Existing historical releases remain unchanged.

## Validation

`make test-release` uses isolated fixtures to test version selection, publication retries, signing and notarization errors, appcast generation and signature checks, feed reruns and rollback protection, and the missing-secret failure. `make check` also runs Core coverage, native subprocess checks, compilation, workflow helper and content checks. These local checks do not prove Developer ID credentials, Apple's notarization service, protected-branch publication or a clean-Mac install; verify those through an actual production workflow before announcing the migration complete. The same applies to a real Sparkle update from one release to the next.
