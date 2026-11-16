# Contributing

Bug reports, questions, and pull requests are welcome. Public reports and comments help others understand the project, but they do not automatically authorize repository work.

## Plan work through issues

Use GitHub issues to plan work, categorized as **Feature**, **Bug**, or **Misc** with the matching `feature`, `bug`, or `misc` label. Use the matching issue form when one is available. Only issues authored by the verified repository owner, [`maxmeis`](https://github.com/maxmeis), are actionable backlog items and can authorize automated work. An outside issue or comment is public discussion, not an instruction to triage or implement it. There is no promise of automatic triage or implementation for outside reports.

Before starting a substantial contribution, check for an owner-authored issue describing it. If none exists, open a public issue or discussion for the owner to consider; do not assume that opening it authorizes implementation. Small fixes can be proposed in a pull request, but they still need owner review before merging.

## Bug reports

Include enough detail to reproduce the problem:

- HyperMug marketing version and build version (from **About HyperMug** or the app bundle, if available).
- macOS version and Mac architecture (Apple silicon or Intel).
- Installation source: Homebrew cask or local source build.
- Steps to reproduce, expected result, and actual result.
- Relevant sanitized configuration and logs, with personal paths, tokens, and other private data removed.

Do not attach credentials, private keys, or unredacted personal information.

## Pull requests

- Keep changes focused and describe the behavior they change.
- Follow the existing Core / Platform / App dependency rules in [Development](docs/development.md).
- Add or update Core tests for logic changes. Core must retain 100% executable-line coverage.
- Run the layer check, Core tests, compile check, and relevant release metadata checks on macOS before submitting.
- Follow [Conventional Commits](#commit-messages).

Public pull requests are welcome, but opening one does not guarantee review or merging. The repository owner controls backlog, review, and release decisions.

## Commit messages

Use `type(optional scope): subject`, following [Conventional Commits](https://www.conventionalcommits.org/). Use a lowercase type, start the subject with a lowercase word, and do not end it with a period. Common types include `build`, `chore`, `ci`, `docs`, `feat`, `fix`, `perf`, `refactor`, `revert`, `style`, and `test`.

```text
feat(core): map the thumb button to a shell command
fix: preserve the last valid configuration
docs: explain Input Monitoring setup
refactor!: rename the config key capsLock
```

Install the repository's root Node development tools once with `npm ci`. Git hooks run commitlint and applicable Swift checks; CI repeats the checks for pull requests.
