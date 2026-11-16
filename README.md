# HyperMug

Menu bar app for macOS: **Caps Lock → Meh/Hyper**, **Caffeine**, and **mouse remapping** for the Logitech MX Master 3S (side buttons, thumb button, scroll direction). All settings live in one JSON file: `~/.config/hypermug.json`.

## Replaces

HyperMug replaces:

- **Hyperkey** — hold Caps Lock = Meh ⌃⌥⌘ / Hyper ⌃⌥⇧⌘, tap = Esc.
- **Caffeine** — left-click the menu bar icon to toggle; right-click for the menu.
- **OpenLogi's button remapping** for the MX Master 3S — Back / Forward / Thumb → shell command or shortcut — plus scroll inversion.

Do not run Hyperkey or OpenLogi at the same time: they fight over Caps Lock and the thumb button. Quit them and disable their login items.

## Menu bar icon

| Click | Action |
|-------|--------|
| **Left-click** | Toggle **Caffeine** for this session (filled mug = on, empty mug = off). Never written to the config file; `caffeineOnLaunch` sets the state at launch. No menu opens. While an app holds [Secure Input](#secure-input), the icon is a lock instead of the mug. |
| **Right-click** or **ctrl + left-click** | Open the menu |

The menu contains only (plus **Blocked by Secure Input: ‹App›…** and a separator at the top while [Secure Input](#secure-input) is on):

- **Settings…** (⌘,) — opens `~/.config/hypermug.json` in your editor (see below). If the file is missing it is recreated first; an invalid file is opened as is and never rewritten.
- **Check Privileges…** — shows whether Accessibility and Input Monitoring are granted (✅/❌). For each missing one a button opens its System Settings pane and triggers the system prompt. A **Restart HyperMug** button is always there (Input Monitoring only takes effect after a relaunch); Return presses OK.
- **Check for Updates…**
- ———
- **Quit HyperMug** (⌘Q)

**Editor.** `Settings…` asks your login shell (`$SHELL -lic`, so PATH and variables match a terminal; 3 s timeout, off the main thread) for `$EDITOR` and runs it detached on the config file, e.g. `EDITOR=cursor` opens it in Cursor. Terminal editors (vi, vim, nvim, nano, emacs, micro, hx, helix, kak, joe, ed, pico, mg) are not run from a menu bar app. If `$EDITOR` is unset, is a terminal editor, or its command fails, the file opens in the default app for `.json` files (TextEdit if none handles them).

Caps Lock mode, Caffeine at launch, mouse settings and start at login (`launchAtLogin`) are set only in the config file. The only thing done from the icon is the session Caffeine toggle.

## Config file

Path: `~/.config/hypermug.json` (the folder is created if missing). It is the single source of truth for every setting.

```json
{
  "$schema": "./hypermug.schema.json",
  "capsLock": "meh",
  "caffeineOnLaunch": true,
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

HyperMug writes a new or empty config file with these values and nothing else: `$schema`, `caffeineOnLaunch: true`, `capsLock: "meh"`, `launchAtLogin: false`, and both scroll inversions `false`. Button mappings are not written until you add them; `buttons` is absent while no button is mapped, and a mapped button contains only its one action key.

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
log stream --predicate 'subsystem == "com.max.hypermug"'
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

If the Command Line Tools compiler and SDK disagree, point `SDKROOT` at the matching SDK:

```bash
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ./build.sh
```

Requires macOS 14+, Apple Silicon.

## Development

The source is split into three layers under `Sources/`:

| Layer | Folder | What lives there |
|-------|--------|------------------|
| **Core** | `Sources/Core/` | All logic and decisions: config model, codec, schema and store, shortcut grammar, HID++ codec and thumb session state machine, Caps/tap/scroll/side-button decisions, caffeine and launch-at-login decisions, Secure Input parsing and quit-protection rules, editor command parsing, update-check decision. Compiled as its own Swift module, `HyperMugCore`. |
| **Platform** | `Sources/Platform/` | Thin adapters to the OS and hardware: event tap, CGEvent posting, IOHIDManager (Caps key and thumb), IOPM assertion, SMAppService, `hidutil`, process spawning and editor launch, IORegistry and `NSRunningApplication` reads, file watching, logging. |
| **App** | `Sources/App/` | AppKit UI and the composition root: entry point, status item, menu, alerts, panels, wiring. |

**Dependency rule:** Core depends on nothing else in the repo. Platform and App may import Core; App may use Platform; Platform must not use App. Platform and App stay thin: they may only guard OS call results, translate OS enums to Core enums, execute what Core returns, and build views. Any other branching belongs in Core.

**Enforcement:**

- `./build.sh` compiles Core as the module `HyperMugCore`, and Platform and App compile against it with `import HyperMugCore`. They see only Core's `public` API, and Core cannot reference Platform or App symbols.
- `./scripts/check-layers.sh` (run first by `build.sh` and `scripts/test.sh`) fails when Core imports anything but Foundation, CoreGraphics or Dispatch, when Core calls an OS side-effect API directly (processes, `UserDefaults`, `NSWorkspace`, timers, run-loop and dispatch sources, the clock, the home directory, logging, `print`, CGEvent posting, event taps) that must come in through injection, when Platform references an App symbol, when a Swift file sits outside the three folders, when `Tests/` imports anything but Core (plus Foundation, CoreGraphics and Carbon for key-code cross-checks), or when selftest code is left under `Sources/`.

**Tests:** `Tests/` is a plain Swift executable (`HyperMugCoreTests`, no XCTest) that tests only Core. Platform and App are deliberately untested (hardware and UI). Run:

```bash
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ./scripts/test.sh
```

It builds Core and the tests with coverage instrumentation, runs them, and **fails unless line coverage of `Sources/Core` is 100%**, listing every uncovered `file:line`. Core is linked as a single object, never as a static archive, so a file the tests never touch cannot hide from the report. Unreachable defensive code is deleted, not covered with filler tests.

## Upgrading from MyMug

HyperMug is a clean rename of MyMug (bundle id, config path, signing identity). No code reads the old `mymug.*` files or settings, so move over by hand:

1. In the old app set `launchAtLogin` to `false` (or remove it under System Settings › General › Login Items), so the old app does not start at login and fight HyperMug over Caps Lock, Caffeine and the thumb button.
2. Quit the old MyMug.
3. Delete the old build: `rm -rf build/MyMug.app`.
4. Move the config: `mv ~/.config/mymug.json ~/.config/hypermug.json`, then change its `$schema` value to `./hypermug.schema.json`. (HyperMug creates `hypermug.schema.json` itself.)
5. Create the new signing identity: `./scripts/create-signing-cert.sh`.
6. Build and start HyperMug, then grant **Accessibility** and **Input Monitoring** again (grants belong to the bundle id and signature).
7. Optional: `tccutil reset All com.max.mymug` removes the old app's leftover permission entries.

---

*Generated with Claude AI — please review before distribution.*
