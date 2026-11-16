import Foundation

/// JSON array literal of every token `parseShortcut` accepts. Built from the parser's own table
/// (`shortcutTokenNames`), so the schema enum and the grammar cannot drift apart.
private let shortcutTokenEnumJSON: String = {
    // Serializing an array of strings cannot fail.
    let data = try! JSONSerialization.data(withJSONObject: shortcutTokenNames, options: [.withoutEscapingSlashes])
    return String(decoding: data, as: UTF8.self)
}()

private func buttonSchema(_ description: String) -> String {
    #"""
{
          "type": "object",
          "description": "\#(description) Set exactly one of shell, shortcut or helper. An omitted mapping runs no HyperMug action.",
          "additionalProperties": false,
          "properties": {
            "shell": {
              "type": "string",
              "description": "Command run via /bin/sh -c in the background, output discarded (minimal PATH: /usr/bin:/bin:/usr/sbin:/sbin). Must not be empty."
            },
            "helper": {
              "type": "string",
              "minLength": 1,
              "description": "Name of a shell command in the top-level helpers object."
            },
            "shortcut": {
              "type": "array",
              "description": "Keyboard shortcut to send, as an array of key names: any modifiers plus exactly one key, e.g. [\"cmd\", \"[\"], [\"meh\", \"k\"] or [\"ctrl\", \"left\"]. Modifiers: cmd, ctrl, alt (opt, option), shift, meh (ctrl+alt+cmd), hyper (ctrl+alt+shift+cmd). Keys: a-z, 0-9, [ ] ; ' , . / \\ - = `, f1-f20, left, right, up, down, escape (esc), return (enter), tab, space, delete (backspace), forwarddelete, home, end, pageup, pagedown. The names are listed in lowercase; \#(AppIdentity.appName) also accepts other letter case.",
              "minItems": 1,
              "items": {
                "type": "string",
                "enum": \#(shortcutTokenEnumJSON)
              }
            }
          },
          "oneOf": [
            {
              "required": ["shell"],
              "properties": {
                "shell": { "minLength": 1 }
              }
            },
            {
              "required": ["shortcut"]
            },
            {
              "required": ["helper"]
            }
          ]
        }
"""#
}

/// JSON Schema (draft-07) for `~/.config/hypermug.json`; the single source of truth, compiled into the binary.
/// The tests check it against `encodeConfig` and the model.
public let configSchemaJSON: String = #"""
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "\#(AppIdentity.appName) configuration",
  "description": "Settings for \#(AppIdentity.appName) (~/.config/\#(AppIdentity.configFileName)). Edits apply within about a second; an invalid file is reported and the last good settings stay active.",
  "type": "object",
  "additionalProperties": false,
  "required": ["$schema", "caffeineOnLaunch", "capsLock", "launchAtLogin", "mouse"],
  "properties": {
    "$schema": {
      "type": "string",
      "description": "Link to this schema (written by \#(AppIdentity.appName)); only used by editors."
    },
    "caffeineOnLaunch": {
      "type": "boolean",
      "description": "Whether Caffeine (keep the Mac awake) is on when \#(AppIdentity.appName) starts. Selecting Stay Awake in the menu toggles Caffeine for the running session only and never changes this file; changing this value while \#(AppIdentity.appName) runs sets Caffeine to it."
    },
    "capsLock": {
      "type": "string",
      "description": "What Caps Lock does. default = unchanged; meh = hold for Ctrl+Opt+Cmd, tap for Escape; hyper = hold for Ctrl+Opt+Shift+Cmd, tap for Escape.",
      "enum": ["default", "meh", "hyper"]
    },
    "launchAtLogin": {
      "type": "boolean",
      "description": "Start \#(AppIdentity.appName) when you log in (Start with Machine)."
    },
    "autoUpdate": {
      "type": "boolean",
      "description": "Check for updates automatically with Sparkle. Defaults to true when omitted."
    },
    "helpers": {
      "type": "object",
      "description": "Named shell commands shared by mouse and trackpad mappings.",
      "propertyNames": { "minLength": 1, "pattern": "\\S" },
      "additionalProperties": { "type": "string", "minLength": 1, "pattern": "\\S" }
    },
    "trackpad": {
      "type": "object",
      "description": "Optional three- and four-finger swipe mappings. Before enabling mappings, disable the matching native macOS trackpad gestures once in System Settings so they do not conflict. Only swipes are mapped; taps are unaffected.",
      "additionalProperties": false,
      "properties": {
        "threeFingerSwipe": {
          "type": "object",
          "description": "Actions for three-finger swipes. Omitted directions run no HyperMug action. Native assignments disabled in System Settings remain disabled.",
          "additionalProperties": false,
          "properties": {
            "up": \#(buttonSchema("Three-finger swipe up.")),
            "down": \#(buttonSchema("Three-finger swipe down.")),
            "left": \#(buttonSchema("Three-finger swipe left.")),
            "right": \#(buttonSchema("Three-finger swipe right."))
          }
        },
        "fourFingerSwipe": {
          "type": "object",
          "description": "Actions for four-finger swipes. Omitted directions run no HyperMug action. Native assignments disabled in System Settings remain disabled.",
          "additionalProperties": false,
          "properties": {
            "up": \#(buttonSchema("Four-finger swipe up.")),
            "down": \#(buttonSchema("Four-finger swipe down.")),
            "left": \#(buttonSchema("Four-finger swipe left.")),
            "right": \#(buttonSchema("Four-finger swipe right."))
          }
        }
      }
    },
    "mouse": {
      "type": "object",
      "description": "Mouse settings (wheel mice such as the MX Master; trackpad and Magic Mouse scrolling is never changed).",
      "additionalProperties": false,
      "required": ["invertScroll"],
      "properties": {
        "invertScroll": {
          "type": "object",
          "description": "Reverse the scroll direction of a mouse wheel, relative to the system's current Natural Scrolling setting.",
          "additionalProperties": false,
          "required": ["vertical", "horizontal"],
          "properties": {
            "vertical": {
              "type": "boolean",
              "description": "Reverse the vertical (main) wheel."
            },
            "horizontal": {
              "type": "boolean",
              "description": "Reverse the horizontal (thumb) wheel."
            }
          }
        },
        "buttons": {
          "type": "object",
          "description": "Button remapping. List only the buttons you remap; a button that is not listed keeps its normal behavior.",
          "additionalProperties": false,
          "properties": {
            "back": \#(buttonSchema("Back side button (mouse button 4).")),
            "forward": \#(buttonSchema("Forward side button (mouse button 5).")),
            "thumb": \#(buttonSchema("Thumb button of the MX Master 3S over Bluetooth (needs Input Monitoring permission)."))
          }
        }
      }
    }
  }
}

"""#

/// Writes the schema next to the config, atomically and only when the content differs.
/// Never fatal: failures are logged.
public func installSchemaFile(dir: URL, log: LogSink) {
    let target = dir.appendingPathComponent(AppIdentity.schemaFileName)
    let data = Data(configSchemaJSON.utf8)
    if let existing = try? Data(contentsOf: target), existing == data { return }
    do {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: target.resolvingSymlinksInPath(), options: .atomic)
        log(.info, "wrote \(target.path)")
    } catch {
        log(.error, "cannot write \(target.path): \(error.localizedDescription)")
    }
}
