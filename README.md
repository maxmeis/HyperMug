# HyperMug

Menu bar app for macOS: **Caps Lock → Meh/Hyper**, **Caffeine**, **three- and four-finger trackpad swipes**, and **mouse remapping** for the Logitech MX Master 3S (side buttons, thumb button, scroll direction). All settings live in one JSON file: `~/.config/hypermug.json`.

## Replaces

HyperMug replaces:

- **Hyperkey** — hold Caps Lock = Meh ⌃⌥⌘ / Hyper ⌃⌥⇧⌘, tap = Esc.
- **Caffeine** — left-click the menu bar icon to toggle; right-click for the menu.
- **OpenLogi's button remapping** for the MX Master 3S — Back / Forward / Thumb → shell command or shortcut — plus scroll inversion.

Do not run Hyperkey or OpenLogi at the same time: they fight over Caps Lock and the thumb button. Quit them and disable their login items.

## Install and update

This repository is also a Homebrew tap. Release downloads and Sparkle update feeds are public HTTPS resources hosted in `maxmeis/HyperMug`.

Each channel becomes installable after its first real release and the generated cask-update PR has been merged into `main`. The [Casks directory](Casks/README.md) deliberately has no placeholder versions or checksums.

```bash
brew tap maxmeis/hypermug https://github.com/maxmeis/HyperMug
brew install --cask maxmeis/hypermug/hypermug
```

For builds from `main`, install the beta/nightly cask instead:

```bash
brew install --cask maxmeis/hypermug/hypermug@nightly
```

The existing separate tap, `maxmeis/homebrew-formulae`, continues receiving both casks automatically. While that tap is private, it requires GitHub access:

```bash
brew tap maxmeis/formulae git@github.com:maxmeis/homebrew-formulae.git
```

Stable and beta install the same `HyperMug.app` and share its config and bundle identity. Install one channel at a time; quit HyperMug and uninstall the current cask before installing the other. The public in-repo tap and release ZIPs work without access to the private separate tap.

Release builds include [Sparkle](https://sparkle-project.org/documentation/) for automatic update checks and signed download, installation, and relaunch. `autoUpdate` controls scheduled checks and defaults to `true`. Set `"autoUpdate": false` in `~/.config/hypermug.json` to disable scheduled checks; **Check for Updates…** remains available for manual checks. Edits apply while the app is running. This setting controls checking, while Sparkle handles download and installation prompts. Each build stays on its own channel: stable reads `appcast-stable.xml`, beta reads `appcast-beta.xml`, both on the repository's `updates` branch. Beta never feeds updates to a stable installation. Local development builds without an update signing key have updating disabled.

Both casks declare `auto_updates true`, so ordinary Homebrew upgrades leave updating to the app. To explicitly update through Homebrew, use `brew upgrade --cask --greedy maxmeis/hypermug/hypermug` (or `hypermug@nightly`). The casks pin immutable versioned release downloads with SHA-256 checksums.

## Menu bar icon

| Click | Action |
|-------|--------|
| **Left-click** | Toggle **Caffeine** for this session (filled mug = on, empty mug = off). Never written to the config file; `caffeineOnLaunch` sets the state at launch. No menu opens. While an app holds [Secure Input](#secure-input), the icon is a lock instead of the mug. |
| **Right-click** or **ctrl + left-click** | Open the menu |

The menu contains only (plus **Blocked by Secure Input: ‹App›…** and a separator at the top while [Secure Input](#secure-input) is on):

- **Settings…** (⌘,) — opens `~/.config/hypermug.json` in your editor (see below). If the file is missing it is recreated first; an invalid file is opened as is and never rewritten.
- **Check Privileges…** — shows whether Accessibility and Input Monitoring are granted (✅/❌). For each missing one a button opens its System Settings pane and triggers the system prompt. A **Restart HyperMug** button is always there (Input Monitoring only takes effect after a relaunch); Return presses OK.
- **Check for Updates…**
- **Trackpad Swipes…** — opens the one-time setup instructions and a button for macOS Trackpad settings.
- ———
- **Quit HyperMug** (⌘Q)

**Editor.** `Settings…` asks your login shell (`$SHELL -lic`, so PATH and variables match a terminal; 3 s timeout, off the main thread) for `$EDITOR` and runs it detached on the config file, e.g. `EDITOR=cursor` opens it in Cursor. Terminal editors (vi, vim, nvim, nano, emacs, micro, hx, helix, kak, joe, ed, pico, mg) are not run from a menu bar app. If `$EDITOR` is unset, is a terminal editor, or its command fails, the file opens in the default app for `.json` files (TextEdit if none handles them).

Caps Lock mode, Caffeine at launch, automatic update checks (`autoUpdate`), mouse settings, trackpad bindings, and start at login (`launchAtLogin`) are set only in the config file. The only thing done from the icon is the session Caffeine toggle.

## Config file

Path: `~/.config/hypermug.json` (the folder is created if missing). It is the single source of truth for every setting.

```json
{
  "$schema": "./hypermug.schema.json",
  "capsLock": "meh",
  "caffeineOnLaunch": true,
  "autoUpdate": true,
  "launchAtLogin": false,
  "mouse": {
    "invertScroll": { "vertical": false, "horizontal": false },
    "buttons": {
      "back":    { "shortcut": ["cmd", "["] },
      "forward": { "shortcut": ["cmd", "]"] },
      "thumb":   { "shell": "open -a 'Mission Control'" }
    }
  }
}
```

### JSON Schema

On each launch HyperMug writes `~/.config/hypermug.schema.json` next to the config, and every config it creates starts with `"$schema": "./hypermug.schema.json"`. Editors such as VS Code then offer autocomplete and validation for the file. Keys the schema does not know are flagged in the editor but tolerated by the app, which ignores them. The `$schema` key itself is optional when you edit by hand.

### Defaults

HyperMug writes a new or empty config file with these values and nothing else: `$schema`, `autoUpdate: true`, `caffeineOnLaunch: true`, `capsLock: "meh"`, `launchAtLogin: false`, and both scroll inversions `false`. Button mappings are not written until you add them; `buttons` is absent while no button is mapped, and a mapped button contains only its one action key. Trackpad bindings are off by default, and `trackpad` is omitted while no swipe is mapped.

Missing top-level keys take the same defaults when reading. A button that is absent, `null`, `{}`, or whose `shortcut`/`shell` is empty keeps its normal behavior (back/forward pass through unchanged; the thumb button is not touched). An empty or whitespace-only config file means all defaults: it is not an error, and HyperMug fills it with the default config automatically.

### `capsLock`

| Value | Caps Lock |
|-------|-----------|
| `"default"` | Normal Caps Lock |
| `"meh"` | Hold = ⌃⌥⌘, tap = Esc |
| `"hyper"` | Hold = ⌃⌥⇧⌘, tap = Esc |

**How it works (like Hyperkey).** In `meh`/`hyper` mode HyperMug reads the raw Caps Lock key from the keyboard via IOHIDManager (usage page 0x07, usage 0x39), so it works whether macOS System Settings has Caps Lock set to "No Action" or left as Caps Lock. While the key is held, the event tap adds ⌃⌥⌘ (Meh) or ⌃⌥⇧⌘ (Hyper) to every key press and release; physically held modifiers are kept. Releasing it within 200 ms without pressing another key sends Esc. Caps Lock itself never toggles in these modes, so its LED stays off. In `default` mode HyperMug does no Caps Lock handling at all. This needs **Input Monitoring** (for the raw key) and **Accessibility** (for the event tap); without Input Monitoring, Caps handling is simply inactive and typing is unaffected.

HyperMug uses no `hidutil` remapping. On launch it removes the Caps Lock → F18 mapping that older MyMug builds left behind; any other key mappings you have are not touched.

### `caffeineOnLaunch` and `launchAtLogin`

`caffeineOnLaunch` (default `true`) is the Caffeine state HyperMug sets when it starts; Caffeine keeps the display awake. Left-clicking the menu bar icon toggles Caffeine **for the running session only**: it never writes the file, so the next launch starts from `caffeineOnLaunch` again. If you change `caffeineOnLaunch` in the file while HyperMug runs, Caffeine is set to the new value right away.

`launchAtLogin: true` registers HyperMug as a login item. It is set only in the config file; there is no menu item for it.

### `mouse.invertScroll`

`vertical` flips the scroll wheel, `horizontal` flips the horizontal (thumb) wheel. Inversion is relative to the current macOS direction, so it works with or without Natural scrolling. Only mouse wheels are affected: trackpad and Magic Mouse scrolling is never modified.

### `mouse.buttons`

Buttons: `back` and `forward` (mouse buttons 3 and 4 of any mouse) and `thumb` (the MX Master 3S thumb button). To remap a button, give it an action object with **exactly one** of these keys. To leave a button alone, **omit it** (`null`, `{}`, an empty string or an empty array are read as unmapped too, but HyperMug never writes them).

| Key | Meaning |
|-----|---------|
| `"shortcut"` | Post a keyboard shortcut, as an array of tokens, e.g. `["cmd", "["]` |
| `"shell"` | Run a command with `/bin/sh -c`. Runs detached, output is discarded. A GUI app gets a minimal `PATH` (`/usr/bin:/bin:/usr/sbin:/sbin`), so use absolute paths for other tools. To open an app, file or URL, use `open`, e.g. `"shell": "open -a Safari"`. |

A mapped `back`/`forward` button no longer reaches apps: both its press and release are swallowed and the action runs once on press. The `thumb` action runs once per press.

### `trackpad`

Map three- and four-finger swipes independently in all four directions. Add `trackpad` alongside `mouse` in your config; each direction uses the same `shortcut` or `shell` action format as mouse buttons:

```json
{
  "trackpad": {
    "threeFingerSwipe": {
      "left": { "shortcut": ["cmd", "shift", "["] },
      "right": { "shortcut": ["cmd", "shift", "]"] },
      "up": { "shell": "open -a Terminal" },
      "down": { "shortcut": ["cmd", "w"] }
    },
    "fourFingerSwipe": {
      "left": { "shortcut": ["ctrl", "left"] },
      "right": { "shortcut": ["ctrl", "right"] },
      "up": { "shell": "open -a 'Mission Control'" },
      "down": { "shell": "open -a Finder" }
    }
  }
}
```

Only listed directions run an action. Each swipe fires once; lift all fingers before the next swipe. Taps, pinches, and rotation are not bindings. Normal two-finger scrolling and mouse-wheel scrolling remain available.

**One-time macOS setup:** open **Trackpad Swipes…** from HyperMug's menu. In **System Settings → Trackpad → More Gestures**, disable the conflicting **Swipe between full-screen applications**, **Mission Control**, and **App Exposé** assignments. If three-finger dragging is enabled, turn it off under **Accessibility → Pointer Control → Trackpad Options**. Grant the app Accessibility and Input Monitoring through **Check Privileges…**; relaunch after granting Input Monitoring.

HyperMug reads raw trackpad contacts; it does not selectively intercept Apple's native swipe actions. Disabling those conflicts is the same setup documented by [BetterTouchTool](https://www.folivora.ai/features/trackpad-gestures/). Native assignments you disable stay disabled until you re-enable them in System Settings. HyperMug does not write trackpad preferences. It also leaves scroll events alone so another trackpad or Magic Mouse cannot have its input swallowed by a remapped swipe. On some setups, the focused app may receive scrolling during that swipe.

Built-in MacBook trackpads and Apple Magic Trackpads use the private `MultitouchSupport` framework. Recognition and action routing are tested independently of that hardware adapter; physical gesture behavior needs validation on the target trackpad.

### Shortcut grammar

A `shortcut` is an **array of key tokens**: any number of modifiers plus **exactly one** key. Tokens are case-insensitive. Examples: `["cmd", "["]`, `["cmd", "shift", "["]`, `["ctrl", "left"]`, `["meh", "k"]`, `["hyper", "f13"]`. A string instead of an array is rejected with an error telling you to use an array.

- **Modifiers:** `cmd`, `ctrl`, `alt` (aliases `opt`, `option`), `shift`, `meh` (= ctrl+alt+cmd), `hyper` (= ctrl+alt+shift+cmd).
- **Keys:**
  - letters `a`–`z`, digits `0`–`9`
  - punctuation `[` `]` `;` `'` `,` `.` `/` `\` `-` `=` `` ` ``
  - function keys `f1`–`f20`
  - arrows `left` `right` `up` `down`
  - `escape` (`esc`), `return` (`enter`), `tab`, `space`, `delete` (`backspace`), `forwarddelete`
  - `home`, `end`, `pageup`, `pagedown`

The JSON Schema lists all of these tokens, so editors autocomplete them.

### Live reload and invalid files

Edits apply within about a second without a restart, including editors that save by atomic replace or delete and recreate the file.

If the file is invalid (bad JSON, unknown `capsLock` value, unparseable shortcut, a `shortcut` written as a string instead of an array, a button with both a non-empty `shell` and a non-empty `shortcut`, wrong value types), HyperMug keeps running with the last good config, logs the error, and shows one **HyperMug config error** alert with a short reason. The same error is not shown again until the file becomes valid. HyperMug never overwrites an invalid file.

Unknown keys are ignored. That includes a leftover `caffeine` key from older versions (replaced by `caffeineOnLaunch`) and an `open` action key: the editor flags them through the schema, the app does not.

### First run

If the file does not exist, HyperMug creates `~/.config` and the file with the default config (see [Defaults](#defaults)). Nothing is imported from other apps or from older settings. An empty config file is initialized the same way. If the file is deleted while HyperMug runs, it keeps the last good config; **Settings…** recreates the file. HyperMug writes the config file only to create or initialize it; it never rewrites a file that already has content.

## Secure Input

When an app turns on macOS **Secure Event Input** (typically a focused password field, and some terminals or password managers), macOS stops delivering keystrokes to every event tap and keyboard tool. While it is on, Caps Lock Meh/Hyper in HyperMug does not work, and neither does Hyperkey or any similar tool. This is a macOS restriction, not a HyperMug setting.

HyperMug checks every 2 seconds and shows which app holds it:

- The menu bar icon changes to a **lock** (`lock.fill`, accessibility label "HyperMug — Blocked by Secure Input (‹App›)") while Secure Input is on, and goes back to the mug when it ends. Left-click still toggles Caffeine.
- The menu (right-click or ctrl + left-click) starts with **Blocked by Secure Input: ‹App›…**, followed by a separator. Clicking it opens the **Secure Input** details panel. If macOS reports no owner, the item reads `Blocked by Secure Input: unknown app…`.

There is no config key for this.

### Secure Input panel

A single reusable **floating HUD panel**: it stays on top of other apps and on every Space (also over full-screen apps), and it can be dragged by its background. It opens just below the menu bar icon, right-aligned to it and kept on screen; reopening it while it is visible keeps the position you dragged it to. Closing it only hides it. It refreshes every 2 seconds while visible. It shows:

- status (on/off) and when HyperMug first saw it on (reset when it turns off);
- the holder: app name, PID, bundle identifier, executable or bundle path, owner user, and whether it is the frontmost app;
- the raw session info macOS reports (`IOConsoleUsers`): user name, uid, on console, and secure-input PID, one line per session.

If Secure Input is off the panel says so and all buttons are disabled. If it is on but macOS reports no owner, the app shows as `unknown app (macOS reports no owner)`.

Buttons:

- **Bring to Front** — activates the holder app.
- **Quit** — asks the app to quit (`terminate`); falls back to `SIGTERM` if that is not possible.
- **Force Quit** — `forceTerminate`; falls back to `SIGKILL`.

**Quit** and **Force Quit** always ask for confirmation, naming the app and its PID, and re-check the protections just before acting. They are disabled, with a one-line reason shown in the panel, for:

- PID 1 or lower, and HyperMug itself;
- processes owned by another user;
- `loginwindow`, `WindowServer`, `SecurityAgent`, `kernel_task` and `launchd`.

A failed kill is reported in an alert. Confirmations and errors are sheets on the panel, so nothing blocks the app.

## Permissions

- **Accessibility** — needed for the keyboard/mouse event tap: Caps Lock Meh/Hyper, side-button mapping and scroll inversion. HyperMug asks at launch.
- **Input Monitoring** — needed for Caps Lock detection (Meh/Hyper) and for the thumb button, which is read over HID++ from the mouse. After granting it, relaunch HyperMug (the **Restart HyperMug** button in **Check Privileges…** does that).

Grants are tied to the app's code signature. Run `./scripts/create-signing-cert.sh` once (see [Build and run](#build-and-run)) so every build is signed with the same identity and the grants survive rebuilds. Without that identity `build.sh` signs ad-hoc, which gives each build a new signature, so macOS asks for both permissions again after every rebuild.

## Thumb button support

Only the **MX Master 3S over Bluetooth** is supported. HyperMug diverts the thumb button (HID++ control `0x00C3`) only while `thumb` is mapped, and restores it when the mapping is removed or HyperMug quits. The diversion is re-applied when the mouse reconnects (sleep, power cycle). Do not run Logi Options+ or OpenLogi at the same time; the result is undefined. If HyperMug crashes, the thumb button stays diverted until the mouse reconnects or is power-cycled.

## Logs

```bash
log stream --predicate 'subsystem == "com.maxmeis.hypermug"'
```

Shows config errors, button/thumb diversion, and permission problems.

## Build and run

One-time setup, so Accessibility and Input Monitoring stay granted across rebuilds:

```bash
./scripts/create-signing-cert.sh
```

It creates a self-signed code-signing identity, `HyperMug Local Signing`, in your login keychain (no sudo, nothing is trusted system-wide) and does nothing if it already exists. `build.sh` uses that identity automatically (override with `SIGN_ID`). The first build may show a dialog saying `codesign` wants to use the key: choose **Always Allow**. If the identity is missing, `build.sh` warns and signs ad-hoc.

Then build and run:

```bash
./build.sh
open build/HyperMug.app
```

`build.sh`, `scripts/test.sh` and `scripts/compile-check.sh` pick the SDK themselves (see `scripts/swift-env.sh`): a `SDKROOT` you set is used as is; otherwise the default SDK is tried with one trivial compile, and if the Command Line Tools compiler and SDK disagree, the SDKs next to the toolchain are tried newest first and the first that compiles is used (logged as `swift-env: using SDK <path>`). The choice is cached in `$TMPDIR` for a day. To force one:

```bash
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ./build.sh
```

Requires macOS 14+, Apple Silicon.

## Release channels and maintainer setup

`release-beta.yml` runs on pushes to `main`; `release-stable.yml` runs only through **Actions → Release stable → Run workflow**, with `main` selected and a new `X.Y.Z` version. Stable authorization checks both the original actor and the person rerunning the workflow against `maxmeis`, before entering the production job. Pushing a tag does not publish a production release.

Each successful release builds and tests the app, signs with Developer ID, submits it to Apple's notarization service, staples the result, and signs the final ZIP with Sparkle's Ed25519 key. Publication creates a versioned GitHub Release and git tag at the built commit, publishes the channel's appcast on the `updates` branch, commits that channel's cask to `maxmeis/homebrew-formulae/Casks/`, and proposes the same cask under this repository's `Casks/` through a channel-specific PR. The other channel's feed and cask are preserved. Production uses `vX.Y.Z`; beta releases are marked prerelease and do not replace GitHub's latest stable release. Cask-only pushes to `main` do not start another beta release.

Before enabling releases:

1. Make `maxmeis/HyperMug` public so downloads and raw appcasts work without authentication.
2. Create GitHub environments named `beta` and `production`. Restrict both to the `main` branch. For `production`, set **Required reviewers** to **only `maxmeis`**, allow self-review (you initiate and approve your own release), and disable administrator bypass. [GitHub environment protection](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments) is configured in repository Settings, not in the workflow YAML.
3. Store production signing credentials and tokens **only in the `production` environment**, never as repository-wide secrets. Populate `beta` separately. Generate a separate Sparkle key pair for each channel, so beta signing access cannot sign a stable app update. Keep the stable key pair for future releases; replacing it without a key-rotation release strands installed clients.
4. Protect `main`: restrict direct pushes to `maxmeis` and require your code-owner approval for contributions. `.github/CODEOWNERS` assigns all files to `maxmeis`, but GitHub must enforce required code-owner reviews in branch settings. Beta's Contents-write tokens can also change release and tap metadata, so separate environment secrets alone do not enforce channel-level publication permissions. Every change that can execute with those tokens needs your approval.
5. Enable **Settings → Actions → General → Allow GitHub Actions to create and approve pull requests** so the release job can propose cask changes. Required code-owner review still applies. The publisher explicitly dispatches CI on the PR's branch when its head has no CI check; dispatched CI also checks commit messages. Only the release jobs have the additional Actions-write permission needed for that dispatch.
6. Add the following secrets and variables to each environment. Neither environments nor signing credentials are created by checking in these workflows.

| Environment secret | Value |
|---|---|
| `DEVELOPER_ID_P12_BASE64` | Base64-encoded Developer ID Application certificate and private key exported as a `.p12` |
| `DEVELOPER_ID_P12_PASSWORD` | Password for that `.p12` |
| `APP_STORE_CONNECT_PRIVATE_KEY` | App Store Connect API private key (`.p8` PEM contents), for API-key notarization |
| `APPLE_ID` | Apple account used for password-based notarization; omitted when using the API key |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password for password-based notarization; omitted when using the API key |
| `SPARKLE_EDDSA_PRIVATE_KEY` | Sparkle private key exported with `generate_keys -x`; the file's contents, not its path |
| `RELEASE_TOKEN` | Optional token with Contents read/write when publishing to a different releases repository; defaults to the job's built-in `GITHUB_TOKEN` for HyperMug |
| `TAP_SSH_PRIVATE_KEY` | Preferred tap authentication: private SSH deploy key whose public key has write access to `maxmeis/homebrew-formulae`; use a separate key per environment |
| `TAP_TOKEN` | Optional alternative to the SSH key: fine-grained token with Contents read/write on `maxmeis/homebrew-formulae` |

| Environment variable | Value |
|---|---|
| `SIGN_ID` | Full identity, e.g. `Developer ID Application: Your Name (TEAMID)` |
| `APPLE_TEAM_ID` | Apple Developer team identifier |
| `APP_STORE_CONNECT_KEY_ID` | API key identifier, when using API-key notarization |
| `APP_STORE_CONNECT_ISSUER_ID` | API key issuer identifier, when using API-key notarization |
| `SPARKLE_PUBLIC_ED_KEY` | Base64 public key printed by Sparkle's `generate_keys`, matching this environment's private key |
| `RELEASES_REPOSITORY` | Optional; defaults to `maxmeis/HyperMug` |
| `TAP_REPOSITORY` | Optional; defaults to `maxmeis/homebrew-formulae` |

API-key notarization takes precedence when configured. Supply the private key, key ID, and issuer ID together. Otherwise supply the Apple account, app-specific password, and team ID. The API key authenticates notarization; the Developer ID Application certificate and its private key sign the app in either mode.

The release job alone receives `contents: write`, `pull-requests: write`, and `actions: write`; the stable authorization job remains read-only. Tap publishing prefers the environment's SSH deploy key and validates GitHub's host keys against its HTTPS metadata API. The temporary private-key file is removed after publication. This lets the default setup publish releases and update the private tap without copying a personal GitHub token into CI.

To obtain Sparkle's pinned signing tools locally:

```bash
source scripts/sparkle.sh
sparkle_prepare
"$SPARKLE_ROOT/bin/generate_keys"
```

Follow [Sparkle's key export instructions](https://sparkle-project.org/documentation/#eddsa-ed25519-signatures) to export the private key for CI; keep that file outside the repository. Use a separate keychain account when generating the other channel's key (`generate_keys --help` describes the account option). The public key goes into the corresponding environment variable; users never receive the private key or either GitHub token.

The workflows share a publication queue with `queue: max`, which preserves up to 100 pending runs instead of replacing pending beta builds. Each beta archive is retained even if its source commit is no longer the tip of `main`; an older run cannot move a channel's feed or cask backwards. Stable dispatch uses the selected run's checked-out SHA and rejects version downgrades. Publication first uploads a draft release and publishes it before advancing the feed or tap. A retry reuses the original published ZIP and metadata, including after a tap push failure; an incomplete unpublished draft can be recreated without deleting its tag. Published assets are never overwritten.

For an update-enabled local build, pass `SPARKLE_PUBLIC_ED_KEY`, `UPDATE_CHANNEL=stable` or `beta`, and optionally `APPCAST_URL`; `APP_VERSION` and numeric or dotted `BUILD_NUMBER` override the bundle versions. Production uses the semantic version as its Sparkle build version; beta uses the workflow run ID. This keeps stable updates in version order even if queued workflows execute out of order. Production builds additionally require `REQUIRE_SIGNING=1` and the Developer ID identity. Local self-signed certificates from `create-signing-cert.sh` are for development.

## Development

The source is split into three layers under `Sources/`:

| Layer | Folder | What lives there |
|-------|--------|------------------|
| **Core** | `Sources/Core/` | All logic and decisions: config model, codec, schema and store, shortcut grammar, HID++ codec and thumb session state machine, Caps/tap/scroll/side-button decisions, per-device trackpad swipe recognition, caffeine and launch-at-login decisions, Secure Input parsing and quit-protection rules, editor command parsing. Compiled as its own Swift module, `HyperMugCore`. |
| **Platform** | `Sources/Platform/` | Thin adapters to the OS and hardware: event tap, CGEvent posting, IOHIDManager (Caps key and thumb), IOPM assertion, SMAppService, `hidutil`, process spawning and editor launch, IORegistry and `NSRunningApplication` reads, file watching, logging. |
| **App** | `Sources/App/` | AppKit UI and the composition root: entry point, status item, menu, alerts, panels, wiring. |

**Dependency rule:** Core depends on nothing else in the repo. Platform and App may import Core; App may use Platform; Platform must not use App. Platform and App stay thin: they may only guard OS call results, translate OS enums to Core enums, execute what Core returns, and build views. Any other branching belongs in Core.

**Enforcement:**

- `./build.sh` compiles Core as the module `HyperMugCore`, and Platform and App compile against it with `import HyperMugCore`. They see only Core's `public` API, and Core cannot reference Platform or App symbols.
- `./scripts/check-layers.sh` (run first by `build.sh` and `scripts/test.sh`) fails when Core imports anything but Foundation, CoreGraphics or Dispatch, when Core calls an OS side-effect API directly (processes, `UserDefaults`, `NSWorkspace`, timers, run-loop and dispatch sources, the clock, the home directory, logging, `print`, CGEvent posting, event taps) that must come in through injection, when Platform references an App symbol, when a Swift file sits outside the three folders, when `Tests/` imports anything but Core (plus Foundation, CoreGraphics and Carbon for key-code cross-checks), or when selftest code is left under `Sources/`.

**Tests:** `Tests/` is a plain Swift executable (`HyperMugCoreTests`, no XCTest) that tests only Core. Platform and App are deliberately untested (hardware and UI). Run:

```bash
./scripts/test.sh
```

It builds Core and the tests with coverage instrumentation, runs them, and **fails unless line coverage of `Sources/Core` is 100%**, listing every uncovered `file:line`. Core is linked as a single object, never as a static archive, so a file the tests never touch cannot hide from the report. Unreachable defensive code is deleted, not covered with filler tests.

### Git hooks and commit messages

Hooks are managed with [Husky](https://typicode.github.io/husky/) and commit messages follow [Conventional Commits](https://www.conventionalcommits.org/). Node comes from [Volta](https://volta.sh/); `package.json` pins it (`volta.node`). Install once per clone:

```bash
npm install
```

This installs Husky, commitlint and the `@commitlint/config-conventional` rules and, through the `prepare` script, sets `core.hooksPath` to `.husky/_`. Check with `git config core.hooksPath`. If your npm config has `ignore-scripts=true`, `prepare` is skipped: run `npm run prepare` once (or `npx husky`) after `npm install`.

**Commit message format:** `type(optional scope): subject`, with a lower-case type from `build`, `chore`, `ci`, `docs`, `feat`, `fix`, `perf`, `refactor`, `revert`, `style`, `test`, a subject that does not start with a capital letter and does not end with a full stop. Examples:

```text
feat(core): map the thumb button to a shell command
fix: clear the Caps remap when the tap is not live
docs: describe the Input Monitoring prompt
refactor!: rename the config key capsLock
```

**What each hook runs** (every hook first runs the repo's vendored hook of the same name from `$(git rev-parse --git-common-dir)/hooks/`, if it exists: the commit-signing check on commit and gitleaks on push. A failure there fails the hook. Those files are never edited):

| Hook | Runs |
|------|------|
| `commit-msg` | `commitlint --edit` (Conventional Commits) |
| `pre-commit` | Always `scripts/check-layers.sh`. Plus `scripts/test.sh` (100% Core coverage) when a staged path is under `Sources/Core/` or `Tests/`, or is `scripts/test.sh`. Plus `scripts/compile-check.sh` when a staged path is under `Sources/` or is `build.sh` or `Info.plist`. A docs-only commit therefore runs only the layer check. |
| `pre-push` | gitleaks, then `scripts/check-layers.sh`, `scripts/test.sh` and `scripts/compile-check.sh`, always. |

`scripts/compile-check.sh` builds the `HyperMugCore` module and type-checks Platform and App against it (no app bundle, no linking, no signing), into a temp directory. The scripts share their Swift settings, including the SDK auto-detection described in [Build and run](#build-and-run), in `scripts/swift-env.sh`, so the hooks need no `SDKROOT` setup.

**CI:** `.github/workflows/ci.yml` runs on every push and pull request on a `macos-latest` runner. It runs the same three scripts plus commitlint over the pushed commits (`npx commitlint --from <base> --to <head>`), so skipping the hooks with `--no-verify` does not get past it. On the runner the default Xcode SDK compiles, so the scripts use it as is.

## Upgrading from MyMug

HyperMug is a clean rename of MyMug (bundle id, config path, signing identity). No code reads the old `mymug.*` files or settings, so move over by hand:

1. In the old app set `launchAtLogin` to `false` (or remove it under System Settings › General › Login Items), so the old app does not start at login and fight HyperMug over Caps Lock, Caffeine and the thumb button.
2. Quit the old MyMug.
3. Delete the old build: `rm -rf build/MyMug.app`.
4. Move the config: `mv ~/.config/mymug.json ~/.config/hypermug.json`, then change its `$schema` value to `./hypermug.schema.json`. (HyperMug creates `hypermug.schema.json` itself.)
5. Create the new signing identity: `./scripts/create-signing-cert.sh`.
6. Build and start HyperMug, then grant **Accessibility** and **Input Monitoring** again (grants belong to the bundle id and signature).
7. Optional: `tccutil reset All com.max.mymug` removes the old app's leftover permission entries.
8. If you ran a HyperMug build from before the bundle id became `com.maxmeis.hypermug`, it used `com.max.hypermug`; `tccutil reset All com.max.hypermug` removes those leftover grants.

---

*Generated with Claude AI — please review before distribution.*
