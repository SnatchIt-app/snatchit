# Home header — SN logo revision (owner-requested, post-Phase 2)

**Session:** Front End · **Date:** 2026-09-03
**Scope:** a single owner-requested change to the approved Phase 2 Home header. Nothing else on Home,
no navigation change, no Core-owned file, no functional change.

## What changed

The Home header's "Snatch It" text wordmark is replaced by the official white **SN** monogram.

- **File:** `src/components/discovery/HomeHeader.tsx` only.
- **Asset:** `brand/sn-logo-white.png` — the existing official white SN mark. Not recreated, not
  regenerated, not a font. Required via the repo's `@/` root alias (`@/brand/sn-logo-white.png`);
  verified to resolve and register in the iOS bundle.
- **Colour:** the asset is already white on transparent, so **no tint** is applied. It sits directly
  on the black header (`v2.surface.canvas` = `#000000`), giving white-on-black at maximum contrast
  (21:1). No black, no red.
- **Geometry:** the intrinsic ratio (1024×371) is pinned with `aspectRatio: 1024/371` at a fixed
  `height: 24`, so the mark cannot be stretched or squashed regardless of rendered height. Rendered
  with `resizeMode="contain"`.
- **No container:** the image is placed directly in the header row — no square, circle, border, badge
  or background plate around it.
- **Compact, brand-mark scale:** 24pt tall, aligned on the header line with the search control
  (`alignItems: 'flex-end'`), not a hero graphic.

## What was kept

- The "Miami" locality label beneath the mark. It is a place tag, not the Snatch It wordmark, and
  removing it would alter the approved Home beyond the requested wordmark swap.
- Safe-area behaviour: the header still reads `useSafeAreaInsets().top` (no hardcoded padding).
- Header height and spacing: unchanged rhythm; the mark occupies roughly the same vertical space the
  wordmark did.
- The search `IconButton` and its alignment.

## Asset selection

Repository SN assets were inspected. The canonical brand directory is `brand/`, which carries both
black and white variants of the same monogram (`sn-logo-black.png`, `sn-logo-white.png`, plus 512px
and SVG forms). The black and white PNGs share identical geometry (1024×371); the black one visibly
renders the **SN** mark, the white one is that same mark white-on-transparent. An official white
asset exists, so it was used directly rather than tinting the black one. No ambiguity between
substantially different SN designs, so no stop-and-report was needed.

## Verification

- **Compiles / bundles:** `tsc` clean; the full iOS bundle builds (HTTP 200) with `sn-logo-white`
  registered as an asset.
- **Contrast:** white `#FFFFFF` on black `#000000` — composited preview confirms the SN mark renders
  solid white on black (60.7% white coverage of the frame), maximum contrast.
- **Aspect ratio:** pinned to 1024/371; cannot distort.
- **No container:** none in markup or style.
- **Home functionality:** unchanged — only the header's brand element changed; feed, filters, search,
  refresh, realtime, navigation untouched.
- **Listing Detail:** zero diff since the Phase 1 commit (`cc77150`).
- **Tests / lint:** 399 passed / 12 files; 36 lint warnings, 0 errors — no new warnings.

## On-device

Rendered/composited verification only. The live on-device look should be confirmed in the dev client
alongside the Phase 3 review; Metro is already serving this worktree.
