# Permissions and troubleshooting

## Permissions

- **Accessibility** supports the keyboard and mouse event tap used by Caps Lock Meh/Hyper, side-button mappings, and scroll inversion.
- **Input Monitoring** supports raw Caps Lock detection and access to the MX Master 3S thumb button.

Use **Check Privileges…** in the menu to see or grant permissions. Relaunch HyperMug after granting Input Monitoring. Permission grants are tied to the app's code signature. Release builds use a stable Developer ID signature; a local build can use the persistent signing identity described in [Development](development.md).

## Common issues

### Caps Lock or mouse input is not remapped

Confirm Accessibility and Input Monitoring are granted, then relaunch after granting Input Monitoring. In `"default"` Caps Lock mode, HyperMug does not handle Caps Lock. If using Meh/Hyper mode, quit other Caps Lock remappers such as Hyperkey to avoid competing input handling.

### A trackpad swipe does not run its action

Check that the direction is configured in `trackpad`, then follow [Trackpad setup](installation.md#trackpad-setup) to disable conflicting native macOS gestures. HyperMug reads raw contacts from supported Apple trackpads; hardware-specific gesture behavior can vary.

### MX Master 3S thumb button is unavailable

Thumb-button remapping supports the MX Master 3S over Bluetooth. Do not run Logi Options+ or OpenLogi at the same time; they can compete for control of the button. If HyperMug crashes while the button is diverted, reconnect or power-cycle the mouse to restore it.

### Configuration error

HyperMug keeps the last valid configuration when a file contains invalid JSON, an unsupported value, or an invalid action. Check the alert and logs, fix the file, and save it again. HyperMug does not overwrite a non-empty invalid file. See [Configuration](configuration.md#validation-and-recovery).

### View logs

Stream HyperMug's unified log from Terminal:

```sh
log stream --predicate 'subsystem == "com.maxmeis.hypermug"'
```

Logs include configuration errors, input diversion, and permission problems. Review output before sharing it and remove personal data.

## Secure Input

When macOS Secure Input is active, the system blocks keyboard event taps. Caps Lock Meh/Hyper will not work during that period. HyperMug shows a lock icon and identifies the reported holder in its menu. This is a macOS restriction and is not controlled by a HyperMug setting.

The menu's **Blocked by Secure Input** item opens a reusable status panel. It refreshes while visible and shows the reported app and process details, including whether it is frontmost. **Bring to Front** activates the reported app. **Quit** and **Force Quit** ask for confirmation and are disabled for HyperMug itself, system processes, invalid process IDs, and processes owned by another user. macOS may report that Secure Input is active without identifying an owner; in that case HyperMug reports an unknown app.
