# HyperMug brand assets

- `HyperMug-Logo.png`: original transparent mark, 1254 × 1254 RGBA. Use as the reusable source for web and other placements.
- `HyperMug.iconset/`: the ten standard macOS icon sizes, derived from the PNG with `sips`.
- `HyperMug.icns`: native macOS app icon compiled from the iconset with `iconutil`.

For the app bundle, copy `HyperMug.icns` to `Contents/Resources` and set `CFBundleIconFile` to `HyperMug` in Info.plist. For the website, derive suitable favicon and touch-icon sizes from `HyperMug-Logo.png`; retain its alpha. Keep the menu bar status symbols for caffeine on/off and Secure Input separate from the app icon.

## Provenance

- Generation tool: built-in `image_gen.imagegen`, with `transparent_background: true`.
- Source image: generated 2026-11-16. No external artwork or API-key CLI was used.
- Final prompt:

> Use case: original HyperMug brand mark and native macOS app icon source. Canvas: genuinely transparent square PNG, ideally 1024 x 1024. Subject: one distinctive simplified coffee mug silhouette, warm gold (#f1b24d) mug body and deep navy (#172e50) precise structural accents. Integrate one subtle keyboard/productivity cue into the mug itself, such as a single small keycap-like facet or notch; two compact angular steam strokes suggest awake/energy. Friendly, precise macOS utility design, flat clean geometric illustration with crisp edges, balanced negative space and generous transparent margin. Strong silhouette and high contrast at 32 px. Single centered standalone symbol, no text or letters, no slogan, no Apple or third-party logo, no watermark, no mockup, no square tile/background, no shadow, no gradients, no tiny decorative details. Output only the original mark on real transparency.
