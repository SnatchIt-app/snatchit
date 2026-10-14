# App icon (iOS, Icon Composer)

- `snatchit-app-icon-1024-v3-transparent.png` — the owner-approved source artwork (1024×1024 RGBA; transparent
  top-centre notch, 282 px ≈ 27.5 % of the width; red ticket, black SN). Copied byte-for-byte from the approved
  generation (sha256 db529867…). Never regenerated or redrawn here.
- `SnatchIt.icon/` — the Apple Icon Composer document that wraps that PNG as a single flat layer (no glass,
  no specular, no shadow, no translucency; background fill "none" so the notch stays transparent). Referenced from
  `app.json` → `expo.ios.icon`; Expo prebuild copies it into the Xcode project and sets
  `ASSETCATALOG_COMPILER_APPICON_NAME=SnatchIt`.
- The previous icon stays at `assets/images/icon.png` (still the root `expo.icon`: Android/other fallbacks) and
  `brand/sn-app-icon-1024.png`. Android adaptive icons and the notification icon are unchanged.
