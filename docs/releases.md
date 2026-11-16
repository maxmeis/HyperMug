# Release process

HyperMug has two public channels. **Stable** is an owner-started workflow with an explicit `X.Y.Z` version and `vX.Y.Z` tag. **Canary** builds automatically when app or branding files change on protected `main`; each published run gets its own `v0.0.0-canary.N` tag and prerelease. A docs, website, skill, or cask-only change does not trigger Canary. Both channels test the exact source commit in GitHub Actions before first tagging; binary releases build from that same SHA.

## Stable: manual app or source

The owner starts **Stable** from `main`, enters `X.Y.Z`, and chooses **Build app** (default on). The `production` environment requires its owner review and permits runs from `main`. The workflow validates the owner actor and triggering actor, the source SHA, version ordering, and the immutable tag. It runs release metadata tests, Core coverage, compile, issue automation, and website checks before publication.

With **Build app** on, the macOS runner signs with Developer ID, notarizes and staples the app, verifies the ZIP and Sparkle signature, and publishes the ZIP, checksum, Stable appcast, and cask metadata in a GitHub Release. It advances only `appcast-stable.xml` and proposes an in-repo `Casks/hypermug.rb` pull request. Review and merge that cask PR before claiming Homebrew availability. A compiled Stable release is the GitHub latest release.

With **Build app** off, the same approved SHA gets an immutable tag and a source-only GitHub Release with GitHub's source archive. It has no app, binary checksum, signing/notarization claim, appcast entry, or cask update, and it is not marked as the latest installable release. Build the source locally with [Development](development.md). The most recent source version may therefore be newer than the most recent downloadable Stable app. Use the Stable feed or merged cask to identify the latest installable Stable version; do not assume `/releases/latest/download/<asset>` exists for a source-only version.

Choose the mode before publishing. A published source-only release cannot gain assets while GitHub immutable releases are enabled; ship a later binary under a **new version and tag**. Do not move tags or replace published assets. A completed source-only retry is a read-only no-op; a compiled retry reuses its immutable published assets. Older versions cannot advance the Stable feed or cask.

## Canary: automatic binary

**Canary** runs on app-related protected `main` pushes. The existing internal `beta` environment holds its separate Canary signing and Sparkle keys and permits only `main`; the public product name and feed are Canary. The runner tests the exact push SHA, creates or verifies an immutable annotated tag, then builds, signs, notarizes, and publishes a prerelease. Its increasing workflow run number identifies the Canary tag and becomes the app/Sparkle build version. Release and feed checks reject a queued run once a newer Canary release exists, so an older run cannot move `appcast-canary.xml` or the `hypermug@canary` cask backward. Canary never advances Stable's feed, cask, or GitHub latest release.

The Canary app embeds its own feed URL and public update key. A Canary installation follows Canary; Stable follows Stable. Both use the same bundle ID and settings, so [switch channels](installation.md#homebrew) by uninstalling the existing cask and installing the other. The older `hypermug@nightly` cask and beta feed are historical and remain untouched; existing beta users migrate manually. A first Canary binary and merged cask PR are required before its Homebrew command works.

## Destinations and controls

Published assets and appcast files live in the configured releases repository; the default is this repository. Each binary release proposes a cask pull request in this protected source repository. The external tap is **optional and off by default** (`PUBLISH_EXTERNAL_TAP=false`) even if `TAP_REPOSITORY` is set. An explicit opt-in requires a writable, non-archived destination and working tap credentials; the archived `maxmeis/homebrew-formulae` repository cannot be used as-is. Neither channel depends on it for in-repo publication. Do not put tokens or signing material in source.

Branch protection, CODEOWNER review, environment rules, and immutable GitHub Releases stay in force. Publishing a GitHub Release does not merge its cask PR or verify an actual installation; release operators still check the downloaded final bytes and installation/update path before announcing availability. See [Casks](../Casks/README.md) and [Installation](installation.md).
