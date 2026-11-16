# Homebrew casks for macOS apps

Researched 2026-11-16. Recheck Homebrew's [Taps](https://docs.brew.sh/Taps), [tap authoring](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap), [Cask Cookbook](https://docs.brew.sh/Cask-Cookbook), [Tap Trust](https://docs.brew.sh/Tap-Trust), and [FAQ](https://docs.brew.sh/FAQ) before publishing: naming, trust, and cask policy can change.

## Resolve the actual tap and artifact

A tap is a Git repository. `Casks/<token>.rb` at the **root of its default branch** is a valid layout, including when the tap is the app's own repository. A separate `homebrew-...` repository is optional, not the default requirement. The one-argument `brew tap owner/name` resolves to `https://github.com/owner/homebrew-name`, **not** necessarily `https://github.com/owner/name`. If the app repository lacks the `homebrew-` prefix, use the explicit URL and fully qualified cask:

```sh
brew tap owner/name https://github.com/owner/name.git
brew install --cask owner/name/token
```

Check the remote and default branch that Homebrew actually cloned. On newer Homebrew versions, a fully qualified cask is the narrow trust path; do not ask users to trust an entire tap by default. For private source repositories, Git authentication for `brew tap` and authentication for the cask's `url` are separate. If users should install publicly while source stays private, host the release asset at a genuinely public endpoint and distribute a public cask; a private GitHub repository's release URL does not become public merely because the cask is public. Never embed a source-repo credential in a cask URL. [Taps](https://docs.brew.sh/Taps), [Tap Trust](https://docs.brew.sh/Tap-Trust), [Homebrew FAQ](https://docs.brew.sh/FAQ).

## Author against a real binary release

Use a stable, versioned release-asset URL and the SHA-256 of the **downloaded final ZIP/DMG**, not a source archive or a pre-notarization file. Keep `version`, `sha256`, `url`, `name`, `desc`, `homepage`, artifact (`app`, `pkg`, etc.), and OS/architecture constraints accurate. Prefer a pinned checksum to `:no_check` for immutable binary assets. A `Casks/token.rb` update belongs on the app repository default branch only after the release asset exists and has been verified; source-only releases cannot produce a usable app cask. [Cask Cookbook](https://docs.brew.sh/Cask-Cookbook).

- `auto_updates true` means the **installed app** downloads and installs its own updates. It is not a generic declaration that a release feed exists; it changes Homebrew upgrade behavior. Use it only when the app actually self-updates. [Cask Cookbook](https://docs.brew.sh/Cask-Cookbook), [Homebrew FAQ](https://docs.brew.sh/FAQ).
- Add `livecheck` only when automatic detection is wrong or insufficient, and verify it selects binary releases rather than a newer source-only GitHub Release. A source-only version must not autobump the cask. [Cask Cookbook](https://docs.brew.sh/Cask-Cookbook).
- Use `uninstall` for components that need explicit removal, especially a `pkg` or `installer` artifact. `zap` is optional in a private tap and performs more complete user-data cleanup only with `brew uninstall --zap`; it is required in the official `homebrew/cask` tap. Never put user-created documents in `zap`. [Cask Cookbook](https://docs.brew.sh/Cask-Cookbook).
- Test the exact tap/cask pair: audit and inspect the cask, fetch the asset, compare SHA-256, install, launch, and uninstall where feasible. `brew update` must reach the default-branch cask. Test on a clean machine or isolated Homebrew environment when trust/cache state could hide a mistake.

If the app has Stable and Canary builds, decide whether users need a separate Canary cask; do not make the Stable cask follow prereleases by accident. A Canary cask needs its own distinguishable token/artifact URL and checksum, plus an explicit user-facing explanation of how it updates and coexists with or replaces the Stable app. Keep each token on its chosen binary channel; `livecheck` must not select a source-only or cross-channel release. An in-app update preference is separate from Homebrew's installed cask version. [Cask Cookbook](https://docs.brew.sh/Cask-Cookbook), [GitHub release management](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository).

## Automate without publishing the wrong version

An app release may trigger a bot to prepare a cask PR **after** the immutable binary asset is public. The bot should fetch the release by exact tag, require the expected asset, verify the version and digest, update only the cask, and leave merge to owner review. A source-only event exits without a cask PR. Make retries bounded and idempotent: if the same cask content or PR already exists, reuse it; transient missing assets may be retried, but wrong/missing checksums must fail visibly. Do not generate a new version or duplicate PR to “fix” a partial run.

For GitHub Actions, distinguish events carefully: ordinary pushes/PR events created by `GITHUB_TOKEN` do not generally start new workflows, while `workflow_dispatch` and `repository_dispatch` are documented exceptions. Dispatch workflows must exist on the default branch to be triggered. Bot-created `pull_request` events may enter an approval-required state. If automatic PR CI is essential, use an appropriately scoped GitHub App installation token or approved fine-grained token and audit the trust boundary. Never run untrusted PR code in a secret-bearing `pull_request_target` job. [GitHub workflow triggers](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow), [event rules](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows), [secure use](https://docs.github.com/en/actions/reference/security/secure-use), [pull_request_target guidance](https://docs.github.com/en/actions/reference/security/securely-using-pull_request_target).
