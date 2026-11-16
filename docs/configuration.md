# Configuration

HyperMug stores all persistent settings in `~/.config/hypermug.json`. It creates the directory and file when needed, writes `~/.config/hypermug.schema.json` beside the file, and watches for edits. Changes normally apply within about a second, including atomic-save edits.

## Example

```json
{
  "$schema": "./hypermug.schema.json",
  "capsLock": "meh",
  "caffeineOnLaunch": true,
  "autoUpdate": true,
  "launchAtLogin": true,
  "mouse": {
    "invertScroll": { "vertical": false, "horizontal": false },
    "buttons": {
      "back": { "shell": "/opt/homebrew/bin/aerospace workspace --no-stdin --wrap-around next" },
      "forward": { "shell": "/opt/homebrew/bin/aerospace workspace --no-stdin --wrap-around prev" }
    }
  },
  "trackpad": {
    "threeFingerSwipe": {
      "left": { "shell": "/opt/homebrew/bin/aerospace workspace --no-stdin --wrap-around next" },
      "right": { "shell": "/opt/homebrew/bin/aerospace workspace --no-stdin --wrap-around prev" }
    },
    "fourFingerSwipe": {
      "left": { "shell": "/opt/homebrew/bin/aerospace workspace --no-stdin --wrap-around next" },
      "right": { "shell": "/opt/homebrew/bin/aerospace workspace --no-stdin --wrap-around prev" }
    }
  }
}
```

On a new or empty file, HyperMug writes the example above: `capsLock: "meh"`, `caffeineOnLaunch: true`, `autoUpdate: true`, `launchAtLogin: true`, both scroll inversions off, and the six AeroSpace mappings shown. These shell actions require AeroSpace at the specified path to work. Existing non-empty files are never rewritten. Missing keys in an existing file retain their previous fallback values; in particular, omitted `launchAtLogin` remains `false` and omitted mappings remain unmapped.

The `$schema` property is optional. The generated file uses `./hypermug.schema.json`, which HyperMug installs beside it. The requested `./hypermug-dev.schema.json` would not resolve with the current schema installer, so the generated link retains the installed filename. Editors that support JSON Schema use it for validation and token autocomplete. The schema flags unknown keys, but the app ignores them for compatibility.

## Settings

| Key | Values and behavior |
| --- | --- |
| `capsLock` | `"default"` leaves Caps Lock alone; `"meh"` maps hold to ⌃⌥⌘ and tap to Escape; `"hyper"` maps hold to ⌃⌥⇧⌘ and tap to Escape. |
| `caffeineOnLaunch` | Whether Stay Awake starts enabled. The menu's checked **Stay Awake** item changes the running session only; it does not edit this preference. |
| `autoUpdate` | Whether Sparkle performs scheduled checks on the installed Stable or Canary feed. Defaults to `true`; manual **Check for Updates…** remains available when false. |
| `launchAtLogin` | Registers HyperMug as a login item when true. |
| `helpers` | Optional names mapped to non-empty shell commands. Mouse buttons and three- or four-finger swipes may reference a name; a command is defined once and shared. |
| `mouse.invertScroll.vertical` | Inverts mouse wheel vertical scrolling relative to the current macOS direction. |
| `mouse.invertScroll.horizontal` | Inverts the MX Master 3S horizontal/thumb wheel relative to the current macOS direction. |
| `mouse.buttons` | Actions for `back`, `forward`, and `thumb` buttons. |
| `trackpad` | Optional `threeFingerSwipe` and `fourFingerSwipe` actions in each of `left`, `right`, `up`, and `down`. |

Scroll inversion affects mouse wheels only, not trackpads or Magic Mouse scrolling.

## Actions and shortcuts

An action object has exactly one non-empty key:

- `"shortcut"`: an array with any number of modifiers and exactly one key, such as `{"shortcut": ["cmd", "shift", "["]}`.
- `"shell"`: a command run detached by `/bin/sh -c`; output is discarded. GUI apps receive a minimal `PATH` (`/usr/bin:/bin:/usr/sbin:/sbin`), so use absolute paths for other tools. Use `open` to launch an app, file, or URL.
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

An absent, `null`, empty, or empty-action button mapping remains unmapped. A mapped back/forward button is swallowed and its action runs once on press; thumb also runs once per press. Trackpad actions use the same action format.

If JSON is malformed, a value has the wrong type, `capsLock` is unknown, a shortcut is invalid, a helper name is missing, or an action combines `shell`, `shortcut`, and `helper`, HyperMug keeps the last valid settings and shows a config error. It logs the reason and never overwrites a non-empty invalid file. Fix the file and save again. Unknown keys are ignored by the app even though the schema may flag them.

**Settings…** (⌘,) opens the native General, Mouse, Trackpad, and Helpers tabs. General edits the launch preference for Stay Awake, not the current session's menu checkmark. Define named shell commands in **Helpers**, then select a helper for a mouse button or swipe direction. Each mapping can be **Unmapped**, a **Shortcut**, a **Shell command**, or a **Helper**; shortcut names may be separated by `+`, spaces, or commas. Renaming or removing a referenced helper requires reassigning its bindings before **Save**. Save validates the full settings snapshot and writes atomically while preserving unknown keys. If another process changed the file since the window loaded, use **Reload** and retry rather than overwriting that edit. **Cancel** closes the window without saving.

**Open Config File…** remains available for advanced JSON editing through `$EDITOR` when it is a GUI editor, or through the default `.json` app. If the file is invalid, repair it there and choose **Reload**; the native editor will not overwrite a non-empty invalid file. External edits continue to reload in the running app.
