# File configuration and runtime diagnostics audit

Audit date: 2026-11-17. Scope: issue [#24](https://github.com/maxmeis/hypermug/issues/24), the menu/settings/configuration lifecycle, native error feedback, subprocess supervision and signed resource packaging. This report describes an engineering audit; it does not claim live accessibility, notification-permission, hardware or first-launch QA.

## Requested skill inputs

Both skills were installed for Codex with the requested skills CLI and read for this change:

- [macos-design-guidelines](https://github.com/ehmo/platform-design-skills/tree/dc2be825d8b439caea78e9eaa8fb3ac23b0ff3e9/skills/macos): native menus/shortcuts, utility windows, actionable error feedback and accessibility.
- [write-swift](https://github.com/emilkowalski/skills/tree/64eb3deb9a5fbfa041faf783e0bc3fd635872e9c/skills/write-swift): value modeling, visible error paths, actor isolation, reentrancy, C interop and resource lifetimes.

The installed Swift compiler is 6.3.3; this repository deliberately retains its existing Swift 5 language mode and macOS 14 target. Unreleased Swift 6.4 syntax and a global concurrency-mode migration are outside scope. Skills are guidance: the user's explicit file-only settings decision takes precedence over a generic Settings-window recipe. A menu-bar utility does not need unrelated document windows or shortcuts on every diagnostic item.

## Findings and changes

| Area | Before | Result |
| --- | --- | --- |
| Configuration ownership | Native Settings and JSON were parallel editors. | Settings/Cmd+, and Doctor configuration actions open the JSON through the existing editor launcher; the custom settings editor and its write path are removed. Session Stay Awake remains in the native menu. |
| Schema packaging | A schema was created beside the config; runtime decoding accepted values the editor schema rejected. | The same Core schema is generated into the variant's signed app resources before codesign. The config gets that resource's actual file URL. Runtime validates the generated structural rules plus native shortcut/helper semantics, without resolving remote schema URLs. |
| Invalid configuration | A modal alert interrupted the utility; unknown keys could be ignored. | Invalid JSON/types/unknown keys/action semantics preserve the last valid config. Nonmodal native notifications open the config; a persistent menu error and Doctor activity remain available when notification permission is denied. |
| Shell execution | Blocking wait on a background worker; unchecked failures; no deadline. | Main-actor lifecycle with process exit sources, bounded concurrency, explicit start/exit errors, a configurable 10-second default deadline and process-group TERM/KILL cleanup. Command contents and output never enter native notifications or shell activity logs. |
| Recovery | Duplicate errors could flood feedback and stale configuration notices remained. | A finite set of categories is coalesced and rate-limited. Recovery clears configuration notices. Permission checks and delivery are tested across await boundaries. |
| Distribution | Legacy Nightly was still offered beside the intended channels. | Only Stable (`hypermug`) and Canary (`hypermug@canary`) are public. The active Nightly cask is removed; immutable historical releases and compatibility conflict checks remain. |

Schema-reference migration only changes `$schema`, preserving existing actual settings and checking for concurrent disk edits before atomic replacement of a symlink target. Invalid files stay untouched. Optional keys can be omitted for fallbacks; mappings must be omitted to disable them. Unknown keys, null/empty action objects and NUL-containing shell strings now fail validation.

Each spawned foreground action uses its own process group and isolated standard streams. At its deadline the group receives TERM, then KILL after 0.5 seconds. The group leader remains unreaped during that grace interval so the group ID cannot be reused. The executor does not claim to contain deliberately daemonized processes that escape that group. Success sends no notification. macOS notification denial is respected.

## Homebrew decision

[Homebrew specifies root `Casks/` for casks](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap#casks); `Formula/` holds formula packages. The signed HyperMug `.app` stays a cask. A local `brew install --dry-run maxmeis/hypermug/hypermug@canary` actually resolved one cask without `--cask`, so the requested simple install syntax needs no incorrect Formula relocation. Docs use an explicit tap URL because this repo has no `homebrew-` prefix. Whole-tap trust is unnecessary; optional pre-install inspection can trust just the Canary cask.

## Validation and limits

Core tests enforce full executable-line coverage for schema/model/store migration, invalid documents, helpers, recovery and notification category policy. Native adapter checks spawn real short-lived child processes to cover fast/nonzero exit, isolation, TERM-ignoring descendants, timeout, capacity and shutdown. A fake notification-delivery adapter exercises authorization, denial, coalescing, recovery and delivery failure without touching the user's macOS permissions. Both app variants are built into isolated disposable output directories and their signed resource paths are checked. CI and release checks run the adapter tests; production packaging asserts its schema before notarization.

Local verification completed: `make check` passed (2,775 Core checks, 2,001/2,001 executable Core lines; 52 release tests; 5 issue-automation tests; 27 real subprocess checks; 13 mock notification checks), layer/shell/compile/content/JS checks, and three changed workflow YAML parses. System `/bin/bash` built both Dev and production variants ad hoc in a disposable directory; strict deep codesign verification passed. Foundation `Bundle.url` resolved each variant’s actual resource, its bytes equaled the compiled schema, and temporary ConfigStore initialization wrote that escaped URL without creating a sidecar. No production signing credentials were used locally.

These tests do not launch the app, modify live configuration/TCC, exercise physical gestures, display a real Notification Center banner or test VoiceOver. Actual Developer ID signing/notarization and artifact verification depend on the subsequent remote Canary run. Stable remains a deliberate versioned owner release, not an invented test release.

Primary platform references: [Apple notification permission](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications), [local notifications](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app), [bundle resource lookup](https://developer.apple.com/documentation/foundation/bundle/url(forresource:withextension:)), [macOS HIG](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos), [posix_spawn](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/posix_spawn.2.html), and [Homebrew tap trust](https://docs.brew.sh/Tap-Trust).
