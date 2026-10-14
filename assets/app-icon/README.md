# App icon (iOS, Icon Composer)

- `snatchit-app-icon-1024-v4-opaque-red.png` — the SHIPPED artwork (RC7): the approved v3 artwork composited over solid
  #EB0217 and written fully opaque with no alpha channel (1024×1024 RGB; former notch now red; every other pixel moved by
  at most 2/255 per channel). Derived deterministically from v3 by the owner's decision "remove the notch entirely and make
  it red" (2026-10-14); nothing redrawn, lettering and proportions untouched.
- `snatchit-app-icon-1024-v3-transparent.png` — the owner-approved source artwork the shipped asset derives from
  (1024×1024 RGBA; transparent top-centre notch, 282 px ≈ 27.5 % of the width; sha256 db529867…). Preserved, not shipped.
- `SnatchIt.icon/` — the Apple Icon Composer document wrapping the shipped PNG as a single flat layer (no glass, no
  specular, no shadow, no translucency; background fill "none": the opaque layer covers the whole canvas, so no
  background shows). Referenced from `app.json` → `expo.ios.icon`; Expo prebuild copies it into the Xcode project and
  sets `ASSETCATALOG_COMPILER_APPICON_NAME=SnatchIt`.
- The previous icon stays at `assets/images/icon.png` (still the root `expo.icon`: Android/other fallbacks) and
  `brand/sn-app-icon-1024.png`. Android adaptive icons and the notification icon are unchanged.
