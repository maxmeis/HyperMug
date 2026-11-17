# File configuration and runtime diagnostics audit

Audit date: 2026-11-17. Scope: issue [#24](https://github.com/maxmeis/hypermug/issues/24), the menu/settings/configuration lifecycle, native error feedback, subprocess supervision and signed resource packaging. This report describes an engineering audit; it does not claim live accessibility, notification-permission, hardware or first-launch QA.

## Requested skill inputs

Both skills were installed for Codex with the requested skills CLI and read for this change:

- [macos-design-guidelines](https://github.com/ehmo/platform-design-skills/tree/dc2be825d8b439caea78e9eaa8fb3ac23b0ff3e9/skills/macos): native menus/shortcuts, utility windows, actionable error feedback and accessibility.
- [write-swift](https://github.com/emilkowalski/skills/tree/64eb3deb9a5fbfa041faf783e0bc3fd635872e9c/skills/write-swift): value modeling, visible error paths, actor isolation, reentrancy, C interop and resource lifetimes.

The installed Swift compiler is 6.3.3; this repository deliberately retains its existing Swift 5 language mode and macOS 14 target. Unreleased Swift 6.4 syntax and a global concurrency-mode migration are outside scope. Skills are guidance: the user's file-only settings decision keeps JSON as the only preferences source; the integrated editor does not introduce a parallel form model. The shared window uses a native JSON editor as the standard Settings destination, with overview, permissions, conflicts and activity alongside it. A menu-bar utility does not need unrelated document windows or shortcuts on every diagnostic item.

## Findings and changes

| Area | Before | Result |
| --- | --- | --- |
| Configuration ownership | Native Settings and JSON were parallel editors. | Settings/Cmd+, and Doctor use the same native HyperMug window. Its Configuration page edits the actual JSON with NSTextView; the former parallel form editor is removed. A byte-comparing ConfigStore save path validates before writing; drafts survive external edits, and close/quit/restart protects unsaved changes. Session Stay Awake remains in the native menu. |
| Schema packaging | A schema was created beside the config; runtime decoding accepted values the editor schema rejected. | The same Core schema is generated into the variant's signed app resources before codesign. The config gets that resource's actual file URL. Runtime validates the generated structural rules plus native shortcut/helper semantics, without resolving remote schema URLs. |
| Invalid configuration | A modal alert interrupted the utility; unknown keys could be ignored. | Invalid JSON/types/unknown keys/action semantics preserve the last valid config. Nonmodal native notifications open the config; a persistent menu error and Doctor activity remain available when notification permission is denied. |
| Shell execution | Blocking wait on a background worker; unchecked failures; no deadline. | Main-actor lifecycle with process exit sources, bounded concurrency, explicit start/exit errors, a configurable 10-second default deadline and process-group TERM/KILL cleanup. Command contents and output never enter native notifications or shell activity logs. |
| Recovery | Duplicate errors could flood feedback and stale configuration notices remained. | A finite set of categories is coalesced and rate-limited. Recovery clears configuration notices. Permission checks and delivery are tested across await boundaries. |
| Distribution | Legacy Nightly was still offered beside the intended channels. | Only Stable (`hypermug`) and Canary (`hypermug@canary`) are public. The active Nightly cask is removed; immutable historical releases and compatibility conflict checks remain. |

The in-app source editor supports native text selection, undo/redo, Find and Command-S; automatic quotes/substitutions are disabled. Validation alone does not apply preferences, malformed drafts cannot replace disk, and explicit Reload/Discard is separate from polling. Configuration notifications route to this same window. Restart confirmation occurs before launching the relaunch helper.

Schema-reference migration only changes `$schema`, preserving existing actual settings and checking for concurrent disk edits before atomic replacement of a symlink target. Invalid files stay untouched. Optional keys can be omitted for fallbacks. Initial files show all button/swipe slots as empty objects (`{}`) when unassigned; an omitted mapping has the same inactive behavior. Unknown keys, null mappings, empty action values and NUL-containing shell strings fail validation.

Each spawned foreground action uses its own process group and isolated standard streams. At its deadline the group receives TERM, then KILL after 0.5 seconds. The group leader remains unreaped during that grace interval so the group ID cannot be reused. The executor does not claim to contain deliberately daemonized processes that escape that group. Success sends no notification. macOS notification denial is respected.

## Homebrew decision

[Homebrew specifies root `Casks/` for casks](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap#casks); `Formula/` holds formula packages. The signed HyperMug `.app` stays a cask. A local `brew install --dry-run maxmeis/hypermug/hypermug@canary` actually resolved one cask without `--cask`, so the requested simple install syntax needs no incorrect Formula relocation. Docs use an explicit tap URL because this repo has no `homebrew-` prefix. Whole-tap trust is unnecessary; optional pre-install inspection can trust just the Canary cask.

## Validation and limits

Core tests enforce full executable-line coverage for schema/model/store migration, invalid documents, helpers, recovery and notification category policy. Native adapter checks spawn real short-lived child processes to cover fast/nonzero exit, isolation, TERM-ignoring descendants, timeout, capacity and shutdown. A fake notification-delivery adapter exercises authorization, denial, coalescing, recovery and delivery failure without touching the user's macOS permissions. Both app variants are built into isolated disposable output directories and their signed resource paths are checked. CI and release checks run the adapter tests; production packaging asserts its schema before notarization.

Local verification includes the full Core coverage gate (2,828 checks; 2,053/2,053 executable lines), 52 release tests, 5 issue-automation tests, 27 actual subprocess checks, 13 mock notification checks and 14 editor-model checks. Layer/shell/compile/content/JS checks and changed workflow YAML parses pass. System `/bin/bash` builds isolated Dev and production ad-hoc bundles and strict deep codesign/resource checks run for both. No production signing credentials are used locally.

`make test-window` actually opened the shared native window in an isolated UI fixture with a temporary JSON file and input capture disabled. Its 19 checks passed: window reuse and minimum size, bounded content, raw text safety, modified state, Undo/Redo synchronization, invalid Save protection, Command-S validation/save/apply, Settings/Doctor navigation, reopening the selected section, and Keep Editing/Discard behavior. This caught and fixed oversized split content, an unsynchronized Undo state and a sheet-close race before shipping. A compositor capture of only that fixture window was visually inspected using existing Screen Recording permission; no permission was requested. The interactive fixture is committed and optional, not part of headless CI.

Tests do not modify live configuration/TCC, run the production input engine, exercise physical gestures, display a real Notification Center banner or test VoiceOver. The native fixture checks the discard controller; it does not actually restart the production app. Actual Developer ID signing/notarization and artifact verification depend on the subsequent remote Canary run. Stable remains a deliberate versioned owner release, not an invented test release.

Primary platform references: [Apple notification permission](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications), [local notifications](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app), [bundle resource lookup](https://developer.apple.com/documentation/foundation/bundle/url(forresource:withextension:)), [native text editing](https://developer.apple.com/documentation/appkit/nstextview), [termination handling](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationshouldterminate(_:)), [macOS HIG](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos), [posix_spawn](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/posix_spawn.2.html), and [Homebrew tap trust](https://docs.brew.sh/Tap-Trust).
