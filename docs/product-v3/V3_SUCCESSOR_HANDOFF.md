# V3 successor — native review handoff

Durable record, kept in the repository rather than in session storage. The previous
handoff lived in a temporary scratchpad and **did not survive**: the `f3f08930` native
captures, the Xcode build log and the `npm ci` log are gone. That is the reason this
file and the archive below exist.

## Candidate

| Fact | Value |
|---|---|
| Commit | see `git log -1` on `v3/midnight-app`; this document is committed **with** it |
| Branch | `v3/midnight-app` |
| Contains | `168e794a` (reserving seam) + the Home feature-selection fix + Listing artwork selection |
| Serving tree | `/Users/josetascon/snatchit-refund` |
| Metro | `:8081`, pid 2172, started 2026-09-26 16:56, cwd verified as the serving tree |
| Device | `SN V3 393x852`, UDID `52282259-961E-4A1A-B32B-CEFA858CFF48` |
| Geometry | iPhone 16, 393×852 pt (measured: 1179×2556 @3×) |
| Runtime | iOS 26.5 (23F77), Xcode 26.6 (17F113) |
| Installed bundle | `com.jdt-inc.snatchit` |
| Native rebuild | **not required** — no native file changed since the installed build |

Metro needs **no restart and no repoint**: it is rooted at the directory whose contents
advanced, so the only action is reloading the app. C operates Metro and the simulator
connection; B operates the app (B confirmed this, `ca00a250`).

## What changed, and why it mattered

**Home — the poster was not reliably reaching the feature.** `withArt` put the feature's
artwork on `rows[0]` and assumed that row was the feature. The screen buckets rows by
event date (`groupByEventDate`), flattens the sections and features `index === 0` of
*that* order. `rows[0]` is the feature only when the fixture's first row falls in the
earliest bucket — which it did for the shipped fixture, so a native capture looked
correct while the rule was wrong. The featured row is now derived with the screen's own
ordering function, and honours the screen's other rule: a sold or ended row is never
featured, so when the first row is ineligible nothing claims a feature that will not
render.

**Listing — no artwork could be selected at all.** Every listing fixture hard-coded
`cover_image_path: null` and the route had no `?art=`, so the listing review could only
see the missing-artwork plate. R-4 moved the identity *beneath* the poster, and that
cannot be judged against no poster.

**Both harnesses now share `src/lib/media/harnessArt.ts`.** Two copies of a selection
rule is how two surfaces end up offering different keys; and a rule inside a `.tsx`
route cannot be imported by a behavioural test, which is how the Home defect survived.

## Routes and controls

`?appearance=light|dark` on every route; it drives the app's own stored preference.

- **Home** — `/_dev/v3-home?variant=…&art=…`
  `variant=` `feed` (default) · `empty` · `nomatches` · `sold-empty` · `ended-empty` · `error` · `offline`
- **Listing** — `/_dev/v3-listing?screen=listing&variant=…&art=…&reserving=1`
  `variant=` default (live) · `sold` · `cancelled` · `not-found` · `on-hold` · `won` · `reserved-by-you` · `own-listing`
  `screen=listing` is required — without it the route's switch falls through and renders nothing.
- **`art=`** (same keys on both) — `missing` · `flyer` · `photo` · `markers` · `tall` · `wide` · `square` · `subject` · `subject-wide` · `all`
- **`reserving=1`** (Listing) — renders the "Reserving…" treatment. It seeds the screen's
  own state, which feeds both the resolver (disabling each action) and `reserveBusy`
  (choosing the button). It starts nothing.

## Verification

**Per-fixture proof that the artwork reaches the FEATURED frame** — read from the
rendered DOM, not from the URL being accepted. Frame 393×491 (4:5) in every case:

| `art=` | rendered in the feature |
|---|---|
| flyer | `flyer-dense-4x5` |
| markers | `markers-4x5` |
| tall | `markers-9x16` |
| wide | `markers-16x9` |
| square | `markers-1x1` |
| subject | `photo-subject-4x5` |
| subject-wide | `photo-subject-16x9` |
| missing | the plate |

Listing harness, same method: `flyer`, `tall`, `subject-wide` and `missing` all match at
393×491.

**Tests:** 172 files / 2921 passing, exit 0; typecheck clean; working tree clean.

**Reproduction kept as a control:** restoring the `rows[0]` rule fails HA1 (the feature
carries nothing) and HA3 (a sold row takes feature artwork) and nothing else.

**Safeguards, asserted rather than assumed:** an unknown `?art=` is dropped rather than
forwarded into the cover field (the value arrives from a URL and lands in the same field
a database row fills); neither harness references the reserve RPC,
`release_reservation`, the payment-intent function, `useSingleFlight`, `handleBuyNow`,
`setReserving`, `confirmPayment` or stripe; both routes redirect outside a sandbox or dev
build; and a module may *name* the bundled-fixture mechanism but only `app/_dev` may
import it.

## Limits

- This is a **Debug dev client**. There is no embedded `main.jsbundle`; JS is served live
  from Metro. Captures prove the serving tree, not a self-contained artifact.
- The per-fixture proof above is **web-rendered from the serving tree**, at the review
  geometry. It is implementation-owner evidence. It is **not** B's independent review and
  **not** native evidence.
- Native captures at this commit are **not yet taken**. Earlier native captures were at
  `f3f08930` and no longer exist.
- None of this replaces verification of the final integrated release artifact.

## Archive

`/Users/josetascon/snatchit-v3-evidence/6100dee1/` — outside session storage.

- `captures-web/home-<art>-dark.png` — the eight fixtures at 393×852
- `logs/feature-fixture-proof.txt` — the per-fixture proof output
- `logs/probe-art.js`, `logs/probe-listing.js` — the probes, so the result is reproducible

No secrets: the archive holds PNGs, a probe script and its output. Scanned for key, token
and password patterns before writing.

## Outstanding

- The authorised push of `v3/midnight-app` and `fix/reserving-seam` is **blocked by this
  session's permission guard** ("Out-of-Place Publication"). It needs a permission rule
  from the owner; it was not worked around.
- Queued, not in this candidate (E, coverage reconciliation `e776e516`): artwork
  selection for Search, My listings, Bids, Tickets, Order, Send, Checkout OrderIdentity
  and Public profile; `edit/[id].tsx` spinner that never stops on the refusal paths;
  `CreateListingScreen` silent failure on a signed-out publish; missing harness variants;
  Send "Transfer not found" has no retry.
