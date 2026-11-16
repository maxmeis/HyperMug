# Homebrew casks

This repository is the public Homebrew tap `maxmeis/hypermug`. After a real release has been published and its cask PR has been reviewed and merged into `main`, install with:

```sh
brew tap maxmeis/hypermug https://github.com/maxmeis/HyperMug
brew install --cask maxmeis/hypermug/hypermug
```

For the beta channel, use `brew install --cask maxmeis/hypermug/hypermug@nightly` after its first cask PR is merged. Homebrew follows the tap's default branch; there is no branch argument to `brew tap`. Each release continues updating the external `maxmeis/homebrew-formulae` tap automatically, while a PR proposes the matching cask here. Review and merge that PR to make the new version available from this tap. The first real release and merge will create each installable cask; this directory intentionally contains no placeholder casks or invented checksums.
