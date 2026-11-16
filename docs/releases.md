# Release process

HyperMug ships new releases on one stable production channel. A release version uses `X.Y.Z` and its source tag uses `vX.Y.Z`. The legacy beta release and nightly cask are historical; this workflow does not publish another beta or nightly version.

## Prepare a release

The repository owner prepares and reviews the version on `main` and confirms CI and release metadata checks pass. This repository does not automatically choose or increment a version. The workflow creates an immutable `vX.Y.Z` tag at the approved `main` commit on first publication. For a retry or promotion, an existing tag must resolve to the same approved source commit; the workflow rejects a tag outside `main`.

## Publish

The owner starts **Release production** from `main`, supplies `X.Y.Z`, and explicitly chooses **Build app** (default: on). The workflow accepts only the repository owner's manual dispatch from `main`. The `production` environment retains its owner reviewer and branch policy. Every run verifies the exact source SHA before testing, creating or checking the tag, and publishing the GitHub Release.

With **Build app** on, the workflow runs release metadata, Core coverage, compile, automation, and website checks on macOS. It then builds, signs, notarizes, publishes the app ZIP and immutable metadata assets, advances the stable Sparkle appcast, and proposes the Homebrew cask update. The generated cask pull request must be reviewed and merged before the updated cask is available from this tap.

With **Build app** off, it runs the same checks, creates or validates the tag, and publishes a source-only GitHub Release. GitHub's tag source archive can be built using [Development](development.md). The source-only release is not marked as the latest installable release and has no binary ZIP, checksum, appcast entry, or cask update. The existing Sparkle feed and Homebrew cask stay on their last compiled version. Do not treat a source-only version as an installed app version.

Choose the release mode before first publication. A published source-only release cannot gain binary assets under GitHub release immutability; a later compiled app needs a new version and tag. Repeating a completed source-only run makes no changes. A compiled release stages all assets in a draft before publication, and a retry reuses published assets rather than overwriting them. The workflow refuses to move a version tag or publish an older version over a newer release.

The release workflow may publish to repositories configured by the owner. Values such as `RELEASES_REPOSITORY` and `TAP_REPOSITORY`, the `production` environment, and its required credentials are operational settings; contributors should not invent, copy, or commit secrets. See [Casks/README.md](../Casks/README.md) for the tap behavior.
