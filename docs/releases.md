# Release process

HyperMug ships production releases on one stable channel. A release version uses `X.Y.Z` and its source tag uses `vX.Y.Z`. There is no beta or nightly release channel.

## Prepare a release

The repository owner prepares and reviews the version in the source, confirms CI and release metadata checks pass, and creates the matching version tag. This repository does not automatically choose or increment a version. The tag alone does not publish a release.

## Publish

The owner starts **Release stable** from the repository's default branch using the manual production workflow and supplies the same `X.Y.Z` version as the prepared tag. The workflow accepts only the repository owner's manual dispatch on the default branch. Its production environment controls access to signing, notarization, Sparkle, and publication credentials.

The workflow runs release metadata tests, Core tests and coverage, and the compile check on macOS. It then builds, signs, notarizes, publishes the stable Sparkle appcast and release assets, and proposes the Homebrew cask update. The generated cask pull request must be reviewed and merged before the updated cask is available from this tap. The first real release and merged cask update are required before the install command in [Installation](installation.md) works.

The release workflow may publish to repositories configured by the owner. Values such as `RELEASES_REPOSITORY` and `TAP_REPOSITORY`, the `production` environment, and its required credentials are operational settings; contributors should not invent, copy, or commit secrets. See [Casks/README.md](../Casks/README.md) for the tap behavior.
