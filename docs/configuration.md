# Configuration

HyperMug stores settings only in `~/.config/hypermug.json`. **Settings…** (⌘,) opens the JSON editor inside HyperMug's single native window. **Doctor…** opens its Overview page; Configuration, Permissions, Conflicts and Activity share that same window. There is no second preferences form or separate settings app. The menu's **Stay Awake** checkmark remains a session-only control.

Edit JSON directly, choose **Validate** to check without applying, and **Save** (⌘S) to validate, write atomically and apply. Standard copy/paste, undo/redo and Find (⌘F) work in the native text editor; smart quotes and text substitutions are disabled. **Reveal File** locates the actual document in Finder. You can also edit the same file with an external editor; saved external changes reload automatically, including atomic saves.

An open clean editor follows external changes. An unsaved draft is never replaced by background refresh. If disk bytes changed since editing began, Save refuses to overwrite them. Copy your draft if needed, then use **Reload**; discarding a modified draft requires confirmation. Closing, quitting or restarting HyperMug also protects unsaved changes. Invalid drafts stay in the editor for repair and never replace the last valid file.

## Example

```json
{
  "$schema": "file:///Applications/HyperMug.app/Contents/Resources/hypermug.schema.json",
  "shellTimeoutSeconds": 10,
  "capsLock": "meh",
  "caffeineOnLaunch": true,
  "autoUpdate": true,
  "launchAtLogin": true,
  "helpers": {},
  "mouse": {
    "invertScroll": { "vertical": false, "horizontal": false },
    "buttons": {
      "back": { "shell": "/opt/homebrew/bin/aerospace workspace --no-stdin --wrap-around next" },
      "forward": { "shell": "/opt/homebrew/bin/aerospace workspace --no-stdin --wrap-around prev" },
      "thumb": {}
    },
    "verticalWheel": { "up": {}, "down": {} }
  },
  "trackpad": {
    "threeFingerSwipe": {
      "up": {},
      "down": {},
      "left": { "shell": "/opt/homebrew/bin/aerospace workspace --no-stdin --wrap-around next" },
      "right": { "shell": "/opt/homebrew/bin/aerospace workspace --no-stdin --wrap-around prev" }
    },
    "fourFingerSwipe": {
      "up": {},
      "down": {},
      "left": { "shell": "/opt/homebrew/bin/aerospace workspace --no-stdin --wrap-around next" },
      "right": { "shell": "/opt/homebrew/bin/aerospace workspace --no-stdin --wrap-around prev" }
    }
  }
}
```

On a new or empty file, HyperMug shows every button, wheel and swipe direction, including unassigned slots as `{}` and an empty `helpers` object. These placeholders run no action; they make available keys visible while editing. It writes the example above: `capsLock: "meh"`, `caffeineOnLaunch: true`, `autoUpdate: true`, `launchAtLogin: true`, both scroll inversions off, and the six AeroSpace mappings shown. These shell actions require AeroSpace at the specified path to work. Existing preferences are preserved; only `$schema` metadata is updated when the installed bundle location changes. Missing keys in an existing file retain their previous fallback values; in particular, omitted `launchAtLogin` remains `false` and omitted mappings remain unmapped.

The schema is generated from the same Core model into the signed app’s `Contents/Resources/hypermug.schema.json` before signing. HyperMug fills `$schema` with that resource’s actual `file://` URL, including URL escaping when the app path contains spaces. The example assumes `/Applications/HyperMug.app`; Homebrew or a custom app location can produce a different URL. Dev uses its own bundled `hypermug-dev.schema.json`. No schema sidecar is created beside your config. Old sidecars can be removed once your editor uses the bundled URL.

Editors can use this local resource for validation and autocomplete. Runtime validation uses the same compiled schema and native shortcut/helper checks; it never downloads a user-supplied `$schema` URL. After moving or upgrading the app, launch it to refresh an outdated reference. `$schema` is optional when writing a file yourself.

## Settings

| Key | Values and behavior |
| --- | --- |
| `capsLock` | `"default"` leaves Caps Lock alone; `"meh"` maps hold to ⌃⌥⌘ and tap to Escape; `"hyper"` maps hold to ⌃⌥⇧⌘ and tap to Escape. |
| `caffeineOnLaunch` | Whether Stay Awake starts enabled. The menu's checked **Stay Awake** item changes the running session only; it does not edit this preference. |
| `autoUpdate` | Whether Sparkle performs scheduled checks on the installed Stable or Canary feed. Defaults to `true`; manual **Check for Updates…** remains available when false. |
| `launchAtLogin` | Registers HyperMug as a login item when true. |
| `shellTimeoutSeconds` | Shell action deadline in seconds, from `1` through `300`; defaults to `10`. At the deadline HyperMug terminates the action’s process group and sends a native notification. |
| `helpers` | Optional names mapped to non-empty shell commands. Mouse buttons, wheel directions and three- or four-finger swipes may reference a name; a command is defined once and shared. |
| `mouse.invertScroll.vertical` | Inverts mouse wheel vertical scrolling relative to the current macOS direction. |
| `mouse.invertScroll.horizontal` | Inverts the MX Master 3S horizontal/thumb wheel relative to the current macOS direction. |
| `mouse.buttons` | Actions for `back`, `forward`, and `thumb` buttons. |
| `mouse.verticalWheel` | Actions for physical vertical wheel steps, `up` and `down`. Unbound by default; see [Wheel bindings](#wheel-bindings). |
| `trackpad` | Optional `threeFingerSwipe` and `fourFingerSwipe` actions in each of `left`, `right`, `up`, and `down`. |

Scroll inversion affects mouse wheels only, not trackpads or Magic Mouse scrolling.

## Wheel bindings

`mouse.verticalWheel.up` and `.down` bind wheel steps to the same actions as buttons and swipes. For example, with the side buttons switching AeroSpace workspaces, the wheel can move focus between windows:

```json
{
  "helpers": {
    "previousWindow": "/opt/homebrew/bin/aerospace focus --boundaries-action wrap-around-the-workspace left",
    "nextWindow": "/opt/homebrew/bin/aerospace focus --boundaries-action wrap-around-the-workspace right"
  },
  "mouse": {
    "verticalWheel": {
      "up": { "helper": "previousWindow" },
      "down": { "helper": "nextWindow" }
    }
  }
}
```

- A mapped direction is consumed: its wheel events no longer scroll, and each wheel step runs the action once. An unmapped direction, and horizontal scrolling, keep scrolling normally.
- `up` means rolling the wheel away from you and `down` toward you, whatever the Natural Scrolling setting. `invertScroll.vertical` does not swap bindings; it only reverses the scrolling of an unmapped direction.
- Clicky wheels count one step per notch. High-resolution or smooth-scrolling wheels accumulate their pixel travel into steps. Steps are at least 150 ms apart, and one continuous roll, such as a free-spinning flick, runs at most three actions; pause for about 0.3 s to continue.
- Only mouse wheels are bound. Trackpad and Magic Mouse scrolling is never consumed.
- Wheel bindings use the Accessibility event tap. Other tools that rewrite scroll events, such as smooth-scrolling utilities, can change what HyperMug sees.

## Actions and shortcuts

An empty action object (`{}`) leaves that slot unassigned. To assign an action, set exactly one non-empty key:

- `"shortcut"`: an array with any number of modifiers and exactly one key, such as `{"shortcut": ["cmd", "shift", "["]}`.
- `"shell"`: a supervised command run by `/bin/sh -c`; output is discarded. GUI apps receive a minimal `PATH` (`/usr/bin:/bin:/usr/sbin:/sbin`), so use absolute paths for other tools. Use `open` to launch an app, file, or URL.
- `"helper"`: the name of a command in top-level `helpers`, such as `{"helper": "mission-control"}`. A helper always resolves to a shell command; nested helper aliases are not supported. An unknown name makes the configuration invalid.

Shortcut tokens are case-insensitive. Modifiers: `cmd`, `ctrl`, `alt` (`opt` and `option` aliases), `shift`, `meh` (ctrl+alt+cmd), and `hyper` (ctrl+alt+shift+cmd). Keys: `a`–`z`, `0`–`9`, `[ ] ; ' , . / \\ - = \``, `f1`–`f20`, `left`, `right`, `up`, `down`, `escape` (`esc`), `return` (`enter`), `tab`, `space`, `delete` (`backspace`), `forwarddelete`, `home`, `end`, `pageup`, and `pagedown`.

For example, a trackpad configuration can be added alongside `mouse`:

```json
{
  "trackpad": {
    "threeFingerSwipe": {
      "left": { "shortcut": ["cmd", "shift", "["] },
      "right": { "shortcut": ["cmd", "shift", "]"] },
      "up": { "helper": "mission-control" }
    },
    "fourFingerSwipe": {
      "down": { "shell": "open -a Finder" }
    }
  }
}
```

This example requires a `mission-control` helper in top-level `helpers`. Omitted directions run no action. Each configured swipe fires once; lift all fingers before the next swipe. Taps, pinches, rotation, and normal two-finger scrolling are not bindings. Configure the conflicting native macOS swipe assignments as described in [Installation](installation.md#trackpad-setup).

## Validation and recovery

Omit a button, wheel or swipe direction, or set it to `{}`, to leave it unmapped. Optional settings may be omitted to use their fallback values; `null`, unknown keys and invalid action values are errors. Empty action values such as `{"shell":""}` or `{"shortcut":[]}` are errors; an empty object is the explicit unassigned form. A mapped back/forward button is swallowed and its action runs once on press; thumb also runs once per press. Wheel and trackpad actions use the same action format.

If JSON or the bundled schema rules fail, a shortcut is invalid, or a helper reference is missing, HyperMug keeps the last valid settings. It never overwrites a non-empty invalid file. A native notification offers **Open Configuration**, opening the same in-app editor; the menu also shows **Configuration Error…** while the file is invalid. Doctor activity records the validation path and reason. Fix and save the file to recover automatically. Renaming or deleting a helper requires updating every reference in the same save; names, including surrounding spaces, remain exact.

## Shell failures and notifications

A command that cannot start, exits nonzero, or exceeds `shellTimeoutSeconds` triggers a native notification. At the deadline HyperMug sends `SIGTERM` to its dedicated process group, then `SIGKILL` after a 0.5-second grace period if necessary, including children still in that group. No unrelated process group is signaled. At most eight shell actions run concurrently; excess actions report a busy error. Quitting HyperMug stops its running groups. Deliberately detached daemons are outside this supervision contract; commands should run their work in the foreground.

Notifications ask for macOS permission when the first problem occurs. Denial is respected: errors still appear in Doctor activity/logs, and invalid configuration remains visible in the menu. Repeated notifications are limited to one per category every 30 seconds; configuration recovery resets that category. Success is silent. Native notification text and shell activity logs contain status and an action ID, never command contents, environment values or shell output. Configuration validation logs can include setting names; review them before sharing.

The in-app editor writes through the running configuration store, so only the actual JSON document persists settings. Save checks schema/action validity and compares the disk bytes with the opened baseline before replacing a symlink target atomically. Editing a draft alone has no effect on input handling or permissions.
