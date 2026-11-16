# Configuration

HyperMug stores all persistent settings in `~/.config/hypermug.json`. It creates the directory and file when needed, writes `~/.config/hypermug.schema.json` beside the file, and watches for edits. Changes normally apply within about a second, including atomic-save edits.

## Example

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
      "back": { "shortcut": ["cmd", "["] },
      "forward": { "shortcut": ["cmd", "]"] },
      "thumb": { "shell": "open -a 'Mission Control'" }
    }
  }
}
```

Defaults are `capsLock: "meh"`, `caffeineOnLaunch: true`, `autoUpdate: true`, `launchAtLogin: false`, and both scroll inversions off. No button or trackpad mapping is enabled until configured. Missing top-level keys use their defaults. An empty file is initialized with defaults.

The `$schema` property is optional. Editors that support JSON Schema use it for validation and token autocomplete. The schema flags unknown keys, but the app ignores them for compatibility.

## Settings

| Key | Values and behavior |
| --- | --- |
| `capsLock` | `"default"` leaves Caps Lock alone; `"meh"` maps hold to ⌃⌥⌘ and tap to Escape; `"hyper"` maps hold to ⌃⌥⇧⌘ and tap to Escape. |
| `caffeineOnLaunch` | Whether Caffeine starts enabled. Clicking the menu bar icon changes the running session only; it does not edit this file. |
| `autoUpdate` | Whether Sparkle performs scheduled stable update checks. Defaults to `true`; manual **Check for Updates…** remains available when false. |
| `launchAtLogin` | Registers HyperMug as a login item when true. |
| `mouse.invertScroll.vertical` | Inverts mouse wheel vertical scrolling relative to the current macOS direction. |
| `mouse.invertScroll.horizontal` | Inverts the MX Master 3S horizontal/thumb wheel relative to the current macOS direction. |
| `mouse.buttons` | Actions for `back`, `forward`, and `thumb` buttons. |
| `trackpad` | Optional `threeFingerSwipe` and `fourFingerSwipe` actions in each of `left`, `right`, `up`, and `down`. |

Scroll inversion affects mouse wheels only, not trackpads or Magic Mouse scrolling.

## Actions and shortcuts

An action object has exactly one non-empty key:

- `"shortcut"`: an array with any number of modifiers and exactly one key, such as `{"shortcut": ["cmd", "shift", "["]}`.
- `"shell"`: a command run detached by `/bin/sh -c`; output is discarded. GUI apps receive a minimal `PATH` (`/usr/bin:/bin:/usr/sbin:/sbin`), so use absolute paths for other tools. Use `open` to launch an app, file, or URL.

Shortcut tokens are case-insensitive. Modifiers: `cmd`, `ctrl`, `alt` (`opt` and `option` aliases), `shift`, `meh` (ctrl+alt+cmd), and `hyper` (ctrl+alt+shift+cmd). Keys: `a`–`z`, `0`–`9`, `[ ] ; ' , . / \\ - = \``, `f1`–`f20`, `left`, `right`, `up`, `down`, `escape` (`esc`), `return` (`enter`), `tab`, `space`, `delete` (`backspace`), `forwarddelete`, `home`, `end`, `pageup`, and `pagedown`.

For example, a trackpad configuration can be added alongside `mouse`:

```json
{
  "trackpad": {
    "threeFingerSwipe": {
      "left": { "shortcut": ["cmd", "shift", "["] },
      "right": { "shortcut": ["cmd", "shift", "]"] },
      "up": { "shell": "open -a Terminal" }
    },
    "fourFingerSwipe": {
      "down": { "shell": "open -a Finder" }
    }
  }
}
```

Omitted directions run no action. Each configured swipe fires once; lift all fingers before the next swipe. Taps, pinches, rotation, and normal two-finger scrolling are not bindings. Configure the conflicting native macOS swipe assignments as described in [Installation](installation.md#trackpad-setup).

## Validation and recovery

An absent, `null`, empty, or empty-action button mapping remains unmapped. A mapped back/forward button is swallowed and its action runs once on press; thumb also runs once per press. Trackpad actions use the same action format.

If JSON is malformed, a value has the wrong type, `capsLock` is unknown, a shortcut is invalid, or an action contains both `shell` and `shortcut`, HyperMug keeps the last valid settings and shows a config error. It logs the reason and never overwrites a non-empty invalid file. Fix the file and save again. Unknown keys are ignored by the app even though the schema may flag them.

**Settings…** opens the config file in the editor selected by `$EDITOR` when that is a GUI editor. Otherwise, it opens the file with the default `.json` app. If the file is missing, this command recreates it; deleting it while the app runs does not reset the in-memory settings.
