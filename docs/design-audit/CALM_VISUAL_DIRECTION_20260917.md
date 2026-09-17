# Calm visual direction — first draft (B, 2026-09-17)

**Owner's brief:** the current UI feels too loud. Reduce oversized condensed headings, all-caps labels, heavy outlines,
bright red blocks and competing warnings — while keeping Snatch It's identity, the black/red foundation, the approved v2
tokens, the accessibility work, the reviewed state copy and every functional flow.

**Nothing in this document is implemented.** No product code, payment logic, auth, transfer rule or database file is
touched. C is running the Line 3 handset pass on the transfer/proof screens; this work stays in
`design/frontend-audit-20260917` as artifacts only.

**Deliverables:** this brief · prototypes `docs/design-audit/prototypes/calm-pass.html` (loud→calm pattern pairs, then Home,
Send Transfer and Checkout at normal **and** largest text) · the ranked plan in §7 · the keep-as-is list in §8 · the exact
files per change in §9.

## 1. The diagnosis: the system is not loud, its usage is

The v2 tokens are a restrained system used at maximum intensity almost everywhere. Four habits produce the loudness, and
all four are usage decisions rather than token defects:

1. **Display type inside content.** Oswald 700 uppercase with negative tracking is the identity, but it is used for screen
   titles *and* state titles *and* empty-state titles *and* sheet titles — so several elements shout on one screen.
2. **Caps eyebrows on every section.** `micro` is 10 px caps at tracking 3.0. As a metadata key it is sharp; as the label of
   every block on every screen it reads as shouting at the user in small print.
3. **Red as ambient decoration.** `border.default` is `rgba(255,26,26,0.15)`, so every card, row and input edge is
   red-tinted. The tokens declare "red means action or attention, never decoration" (`DESIGN_SYSTEM_V2.md:18`) and then put
   red on every hairline in the app, which spends the colour before an action needs it.
4. **Every notice at the same intensity.** Amber washes, red pills, bordered warning boxes and countdown chips stack on the
   task screens (six decorated surfaces on Send Transfer, measured), so nothing ranks.

**What stays exactly as it is:** #000 canvas, `#FF1A1A` as *the* action colour, Oswald as the display face, Inter as the UI
face, radius 0, no shadows, tabular prices, the red-on-black signature. The calm pass changes frequency and role, not
vocabulary — a quieter room, not a different one.

## 2. Too loud → calmer (rendered side by side in the prototype)

| Pattern | Now | Calmer | Why it reads as calmer |
|---|---|---|---|
| In-content headings | Oswald 700 caps at `displaySm`–`displayLg` | Inter 600 `title` 17/22, sentence case | One display element per screen — the title in the bar. Hierarchy comes from case and family, not from size |
| Section labels | `micro`, 10 px caps, tracking 3.0 | new `eyebrow`: Inter 500, 11/15, tracking 1.2, sentence case, `text.muted` | Still a label, no longer a shout. Caps kept for badges and table keys, where they are short |
| Hairlines | `rgba(255,26,26,0.15)` on every surface | `rgba(255,255,255,0.10)`; red becomes `border.accent` for selection, focus and active only | Red regains meaning the moment it appears |
| Warnings | Full amber wash, 1 px amber border, stacked | One `Notice`: 2 px left rule in the tone colour, `rgba(255,255,255,0.04)` fill, sentence-case title | One voice per state; cautions move into the collapsed instructions |
| Selected chip / count badge | Red border + red 10% fill / solid red badge | White 8% fill + white 20% border / outlined badge | Selection stops competing with the primary action |
| Primary actions | Multiple red blocks per screen | Exactly one filled red action per screen; secondary = white 20% outline; destructive = error text, never filled | The eye finds the action instead of choosing among reds |
| Surfaces | Cards inside sections, each with its own border | Fill **or** hairline, never both; groups separated by 32 pt rhythm | Fewer boxes, more air, same information |

**Measured on the prototype** (browser, 375 px): Home and Send Transfer contain **zero** red-filled blocks and **zero**
red-bordered elements; Checkout contains exactly **one** red-filled block — the Pay button. Each frame contains exactly
**one** Oswald element. Every frame with a primary action keeps it visible without scrolling, at normal *and* largest text.

## 3. The restrained hierarchy

**Typography.** Screen title: Oswald `displaySm` 20/25 caps, one per screen, in the bar. Content title: Inter 600 17/22.
Body: Inter 400 15/22. Secondary: 13/18 muted. Eyebrow: 11/15, tracking 1.2. Price: Inter 700 20, tabular. Display tokens
above `displaySm` are reserved for the wordmark and marketing surfaces — not app screens.

**Colour roles.** Red: the one primary action, selection/focus, and a live-auction accent. Amber: a state the user must act
on. Error red: a failure that already happened. White inks at 100/70/55/30 carry everything else. Nothing decorative is red.

**Surfaces.** Canvas #000 for the page; `#0A0A0A` for a grouped block; `#111` for sheets. A block gets a fill *or* a
hairline, never both, and never a nested bordered card inside a bordered section.

**Spacing.** 32 between sections, 12 inside a block, 16 screen gutter — the rhythm the design doc already specifies.

**Buttons.** One filled primary per screen (min-height 52), secondary as a neutral outline, destructive as error-coloured
text, ghost as text. Disabled keeps its shape and carries its reason as a sub-line, so no separate warning is needed.

**Notices, three ranks.** *Blocking* — amber rule, owns the CTA's reason, at most one per screen. *Advisory* — neutral rule,
explains a state the user cannot change (a hold, a review window). *Ambient* — plain muted text, no rule, no box.

**Navigation.** Unchanged: the dock keeps its approved 33 pt geometry, its white active capsule and its keyboard drop-out.

## 4. Largest accessibility text
Display type stays capped at `MAX_DISPLAY_FONT_SCALE` 1.3 and body scales freely, which the calm hierarchy survives because
the distinction between a 20 px Oswald title and a 17 px Inter title is **case and family**, not two points of size. In the
prototype at the largest step: Home drops to one column and 3:2 art so titles and prices stay on one line; Send Transfer
keeps the action pinned and the disabled reason readable, with the summary rows scrolling rather than pushing the button off
screen; Checkout keeps its price column aligned through tabular figures and never abbreviates the Pay amount.

## 5. Send Transfer as the clearest example
One primary action on a sticky bar · one blocker, stated once, carrying the button's reason · expiry told as a consequence
("you can still send while this transfer is open; if it closes first, the sale is cancelled and refunded") rather than a red
alarm that gates nothing · proof as its own quiet section with a real thumbnail · instructions collapsed to one row that
keeps its metadata (5 steps · about 3 minutes · 3 cautions) · summary last. **Four surfaces instead of six, none of them
red.** The attestation moves onto the enabled button's sub-line, so the claim is made by the tap.

## 6. Motion — purposeful only
Built on RN `Animated` and the existing `v2.motion` tokens (`instant 90 / swift 180 / settle 280`), because Reanimated
4.1.6 is installed with **no Babel config** and no worklet has ever run in this build. Four transitions, nothing else:
image replacement (crossfade 180 ms, reusing `expo-image`'s existing prop), notice appear/clear (height+opacity 280 ms),
loading (the existing skeleton pulse and `pendingLabel`, unchanged), completion (state block fades in 280 ms while the
action row fades out 180 ms, with the existing success haptic). Reduce Motion: every one collapses to an instant swap
through the existing `useReducedMotion()`. No decorative movement, no shimmer, no spring, nothing that delays a tap.

## 7. Ranked plan

**Release-critical usability (unchanged by the calm pass, and still first):** the bid screen's `0`-floor form after a
discarded fetch error · three destructive actions with no busy state · Home's filter fetches showing "nothing here" while in
flight · the avatar spinner clearing before its write. All C's, none of them visual. *(The checkout offline finding is
withdrawn — it was wrong; see the audit §3b/§14. What survives is a setup-path copy gap, polish.)*

**Calm polish, in dependency order:** (1) the `eyebrow` token and the in-content title rule — mechanical, no layout change ·
(2) the neutral hairline and `border.accent` role — **owner decision, one token, whole-app effect** · (3) the `Notice`
primitive, then retire the hand-rolled warning boxes · (4) neutral chip/badge selection · (5) Send Transfer's re-order,
**after C's handset pass** · (6) the five legacy-token components retired onto v2 · (7) the four motion transitions ·
(8) the lint guard, last.

## 8. Keep as is
The v2 tokens and `textStyle()` · the `ui/` primitives (`Button`, `Badge`, `Chip`, `Input`, `StateView`/`EmptyState`/
`ScreenState`, `Sheet`, `StickyBar`, `Skeleton`, `Spinner`, `MediaUpload`, `usePressScale`) · `AdaptiveDock` with its
approved geometry · `useReducedMotion()` and its nine call sites · the reviewed state copy in `src/lib/ui/loadState.ts` ·
F-SELL-2's `useTopInset()`, the fixed 20 pt badge, `MAX_DISPLAY_FONT_SCALE`, the 1.25 line-height floor · Tickets, Bids
(with F-BIDS-1), Report, and Checkout's payment-state handling — including the reachable/unverified/**unreachable**
distinction A corrected me on · the four haptic meanings · tabular prices · radius 0 · no shadows.

## 9. Exact files each proposed change would touch

| Change | Files / components |
|---|---|
| `eyebrow` token + in-content title rule | `src/theme/v2.ts` (+`type.eyebrow`), `src/theme/typography.ts` (+mapping), **and the byte-identical mirror** `packages/design-tokens/src/brand.ts` — `tests/product-v2-foundation.test.ts:49-52` asserts `expect(pkg.brandTokens).toStrictEqual(mobile.brandTokens)`, so a token move is always both files plus that test (B verified the assertion; A verified it independently). **And it does not reach the web app**: `packages/design-tokens/src/brand.ts:9` says the vendored tarball web installs from "renders the legacy palette until the package is repacked", so any token proposal must state which it intends — mobile-only, or mobile plus a repack. Then per-screen: `ui/StateView.tsx`, `ui/Sheet.tsx`, `ui/EmptyState.tsx`, `listing/ListingStatusBanner.tsx`, both `app/transfer/*/[id].tsx`, `app/settings/*` section labels |
| Neutral hairline + `border.accent` | `src/theme/v2.ts`, `packages/design-tokens/src/brand.ts`, the parity test; consumers inherit. Explicit overrides to review: `ui/Input.tsx` (focus), `ui/Chip.tsx`, `ui/StickyBar.tsx`, `ui/Sheet.tsx` |
| `Notice` primitive, three ranks | new `src/components/ui/Notice.tsx` + `ui/index.ts`; replaces hand-rolled boxes in `app/transfer/send/[id].tsx:292-299`, `app/transfer/receive/[id].tsx:309-318`, `app/settings/index.tsx:295-318`, `src/screens/CreateListingScreen.tsx:822-836` (removing its four invented hexes), and `SecurityNoticeBanner.tsx` becomes its blocking instance |
| Neutral selection | `src/components/ui/Chip.tsx`, `src/components/ui/Badge.tsx` |
| Button hierarchy | `src/components/ui/Button.tsx` (secondary border token only) |
| Send Transfer re-order | `app/transfer/send/[id].tsx` only, plus `ui/StickyBar.tsx` reused. **Not while C's pass is on that screen** |
| Legacy retirement | `PlatformInstructions.tsx`, `DeliveryInfoForm.tsx`, `ProofImageViewer.tsx`, `PriceDisplay.tsx`, `VerifiedSellerBadge.tsx`; delete `StatCardStrip.tsx`, `TransferStatusBadge.tsx` (+ `tests/premium-transfer-wording.test.ts:87`), `src/constants/theme.ts` |
| Motion | `src/components/ui/MediaUpload.tsx`, the new `Notice`, `app/transfer/send/[id].tsx`, `app/transfer/receive/[id].tsx`; all through `useReducedMotion()` |
| Lint guard (last) | `eslint.config.js` |

## 10. What B cannot verify
No device, no simulator, no screenshot of the running app. Every claim here is source-derived or measured in a browser
reconstruction; "largest text" is simulated by scaling the type tokens. Real Dynamic Type, iOS font metrics and the live
badge inset are C's to observe. One decision is the owner's, not B's: whether the default hairline stops being red — and if approved it should land **alone**, since it is the only calm change that alters every screen at once, which makes it the one change that must stay cleanly revertible (A concurs, and wants the same treatment for the dead-code and stale-doc cleanups).
