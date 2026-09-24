# Migration notes — transfer, report, bids, tickets group

**B · 2026-09-24.** Source trace at `v3/midnight-app` @ `2619b9e1`, **97 colour accesses across 7 files,
zero hard-coded literals, none importing the palette.** The per-access mapping is mechanical for **90 of
97**. What follows is the rest — the cases a find-and-replace would get wrong.

> **Evidence: source + computed.** Not rendered review, not device verification.

---

## F-31 — the outbid toast's label fails in Daylight. **Verified, not inherited.**

`OutbidToast.tsx:74,77` — `backgroundColor: v2.status.error`, `color: v2.text.inverse` (`#000000`), label
set in `textStyle('label')` = **12pt bold, which is not large text**, so 4.5:1 applies.

| | Fill | Black label | White label |
|---|---|---|---|
| Midnight | `#FF4D4D` | **6.42:1 — passes** | 3.27:1 |
| Daylight | `#C41414` | **3.46:1 — FAILS** | **6.07:1 — passes** |

**A one-to-one token swap breaks it.** `status.error` is a *light* red on Midnight and a *dark* red on
Daylight, so the label must flip with the scheme — unlike `brand.onRed`, which is black in both because
`brand.red` is the same value in both.

**Fix: add `status.onError` — black on Midnight, white on Daylight.** Same shape as `brand.onRed`, opposite
behaviour, and both measured above. **`text.inverse` is the wrong token here regardless**: it is documented
as text on *brand* red and is being used on *status* error.

---

## Six more that are not mechanical

| # | Where | Why it needs a decision |
|---|---|---|
| **N-1** | `receive/[id].tsx:599` — the **letterbox behind the seller's proof screenshot** (`resizeMode="contain"`) | `surface.surface` becomes `#F4F4F6` in Daylight: near-white bars under a seller photo. Letterboxing is conventionally a fixed neutral, and `onArt` covers text on art, not backgrounds **behind** it. A ruling, not a swap |
| **N-2** | `status.warning` used as a **border** — `receive:590,593,602`, `send:521` | The Daylight value `#8A5400` was solved as a **text** colour. As a 1px box edge it reads as dark brown where Midnight reads bright amber. Token correct, visual result materially different — must be looked at, not assumed |
| **N-3** | `BidCard.tsx:127` (`opacity: 0.55` on the artwork) · `TicketEventGroup.tsx:134` (0.92) | **Opacity dims toward the canvas.** "Dimmed = past" becomes "washed out = past" on white. No token involved; needs a different technique or a per-scheme value |
| **N-4** | `report/[type]/[id].tsx:113,147` — input underline at rest, unselected radio ring | `border.strong` → **`border.control`**. Identical hex today, so zero visual change — but `control` is the key graded at 3:1, and these are control edges, not dividers. A free semantic correction |
| **N-5** | `send/[id].tsx` — `:527`, `:533`×2, `:537`, `:538` | **Five of that file's 26 accesses are in dead styles** (`hint`, `stateBlock`, `stateSub`, `stateWarn`); the JSX uses the shared `StateBlock`. Delete rather than migrate |
| **N-6** | `receive:554`, `send:482`, `TicketEventGroup:44` | Module-level subcomponents (`Row`, `StateRow`) close over a module-level `StyleSheet`. They must become `makeStyles(palette)` + `useMemo` with styles threaded down — the structural part of the work, not a token edit |

---

## N-7 — how this defect will actually look on the phone

**Not as uniformly dark screens.** All four of `receive`, `send`, `BidCard` and `TicketEventGroup` already
render **migrated** children — `Badge`, `Button`, `Spinner`, `MediaUpload`. On a light canvas those children
render Daylight correctly **inside a parent still rendering Midnight**.

**So the symptom is internally inconsistent cards**: a light button on a dark panel, a themed badge on an
unthemed row. Anyone checking for "dark screens in light mode" will miss it. **Look for mismatched
children, not dark screens.**

---

## Also worth stating

`report/[type]/[id].tsx:153` — the "0 / 1000" counter uses `text.faint`, which is **below 4.5:1 in both
appearances**. It is task-relevant near the cap. **Pre-existing, not caused by this migration**, and not
mine to change in an appearance pass — recorded so it is not mistaken for new damage.
