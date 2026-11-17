# Homebrew cask

This repository is also the public Homebrew tap. Install Production with:

```sh
brew tap maxmeis/hypermug https://github.com/maxmeis/hypermug
brew install --cask maxmeis/hypermug/hypermug
```

Update using `brew upgrade --cask maxmeis/hypermug/hypermug`, then quit and reopen the app. The app does not update itself, so the cask does not declare `auto_updates true`.

`Casks/hypermug.rb` points to a versioned, signed and notarized `HyperMug.app` ZIP in this repository's GitHub Releases. Its SHA-256 is calculated from the final archive. A macOS application belongs in `Casks/`; `Formula/` is used for source-built tools. No separate `homebrew-*` repository is needed.

The Production release workflow commits the verified cask directly to `main` after publishing the release. It uses a repository-scoped SSH deploy key when protected-main writes require one, with `GITHUB_TOKEN` as the default for branches that allow it. It needs the direct-push permission described in the [release process](../docs/releases.md#repository-configuration). Cask-only commits do not produce another release. The previous Canary cask is retired; historical releases are preserved.

**HyperMug Dev** is built locally with `make dev` and has its own app identity, configuration and permissions. It is not distributed by this tap.
