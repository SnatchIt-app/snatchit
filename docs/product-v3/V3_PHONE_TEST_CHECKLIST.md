# V3 phone test — the one ordered checklist

**C, 2026-09-24. Candidate: build 23 (`65cb7633-0eca-4314-b135-fd9c90db8214`), commit `9c6c9bf4`, iOS
`preview` internal, sandbox `ofaidukbieeekqaboscm`.** Branch head is `24b021a3`; §6 lists what the build does
**not** contain. This document authorises nothing: the steps marked **APPROVAL** cannot run until the owner
approves the matching line on A's fixture sheet (`docs/release/SANDBOX_V3_FIXTURE_APPROVAL_SHEET_20260924.md`
@ `7dae4815`, revision 2, **not approved**), and that sheet's §0 adds its own gate — the first write comes no
earlier than 15 minutes before the first device step, with A's T0 capture matching.

## 0 · How to read the two classifications

**Writes.** Three values, and they are not interchangeable:

| | Meaning |
|---|---|
| **none** | Nothing leaves the phone for the domain data. Reads happen (RLS-scoped selects); no row is created or changed |
| **device-local** | Written on the phone only — the appearance choice in AsyncStorage. Never reaches the server |
| **SERVER RECORD** | A row is created or changed on the sandbox. Named exactly, per step |

**One server write is unavoidable and is not on A's sheet: step 1.** Launching the build while signed in
registers this device's push token (`register_push_token`, or a legacy insert into `push_tokens`). If that
token was previously bound to another account the server opens a *challenge*; on this sandbox, dispatch is
refused by configuration (A's option (b)), so no notification is delivered. Everything from step 2 to step 24
is **none** or **device-local** — those are the fixture-free checks, and they must not be described as
needing approval. Steps 25+ create records and wait on the owner.

**Evidence class.** What a passing step actually proves:

| | Proves |
|---|---|
| **device-rendered** | This build painted these colours at this text size on this phone |
| **data-path** | The screen retrieved real rows for a real account and rendered them — the only class that proves retrieval |
| **synthetic-gallery** | A component rendered correctly **from props supplied in code**. It proves rendering and nothing about retrieval, RLS, or whether the app can reach that state at all |

---

## 1 · Install and first launch — writes a push-token row

| # | Step | Proves | Writes | Evidence |
|---|---|---|---|---|
| 1 | Install build 23 on the owner's iPhone (the provisioning profile already carries UDID `00008130-000E59801198001C`) and sign in as the DV buyer `sandbox-buyer@snatchit.test` | the build installs, launches and authenticates | **SERVER RECORD:** one `push_tokens` row for this device (challenge possible on rebind; dispatch refused on this sandbox) | data-path |
| 2 | Confirm the SANDBOX badge is present, and that no "Build misconfigured" blocker appears | the build is paired to the sandbox, not production, and the env guard passed | none | device-rendered |

## 2 · Startup appearance — the flash is the point (D-9)

Run 3–6 with the phone in **Light**, then repeat with the phone in **Dark**.

| # | Step | Proves | Writes | Evidence |
|---|---|---|---|---|
| 3 | Force-quit, set the phone to Light, relaunch, and **watch the first painted frame** | no Midnight frame appears before the stored choice is read (the provider withholds its tree; the splash is held until fonts and the choice are both ready) | none | device-rendered |
| 4 | Settings → Appearance → **Light**. Force-quit. Relaunch | the explicit choice survives a cold start, and the first frame is Light | device-local | device-rendered |
| 5 | Settings → Appearance → **Dark** with the phone still in Light. Force-quit. Relaunch | an explicit choice overrides the phone, across a relaunch | device-local | device-rendered |
| 6 | Settings → Appearance → **System**. Without leaving the app, flip the phone's appearance in Control Centre | the app follows the phone live, with no restart | device-local | device-rendered |
| 7 | In each of the three settings, check the **status bar glyphs** and the **keyboard** (open any text field), then a **native dialog** (Settings → Sign out → cancel) | the native surfaces follow the app, not the phone | none | device-rendered |

## 3 · Every reachable surface, in both appearances — no records created

Steps 8–20 are **read-only**. Run each one twice, once in Light and once in Dark. The three live listings
(`c343406e`, `b1c3c478`, `58cc00e3`) end **2026-09-25 02:01:44Z**; after that, steps needing a live listing
need decision D1 first, so run this section before then if possible.

| # | Step | Proves | Writes | Evidence |
|---|---|---|---|---|
| 8 | Home — feed rows, the featured card, the SN mark, the market label | the mark is tinted (a white monogram would be invisible on white); over-artwork text is legible on a real flyer, not near-black | none | data-path |
| 9 | Home — pull to refresh; then turn on Airplane Mode and pull again | the refresh tint and the failure notice both read in both appearances | none | data-path |
| 10 | Explore — the filter chips and the filter sheet, selected and unselected; the sheet's **grabber** | chips identify as controls (graded edge) and the sheet reads as draggable | none | device-rendered |
| 11 | Listing detail on a live listing — hero, provenance, seller trust row, the **Verified Seller** badge, the transaction panel, the status banner | over-artwork identity lines are legible; the verified blue is not the 2.28:1 literal it used to be | none | data-path |
| 12 | Listing detail — the **primary and secondary actions**, pressed and disabled | the pressed red is the one agreed value; a disabled control still reads as a control | none | device-rendered |
| 13 | **The three-row bid summary**: open the bid screen on a live listing and move the amount — **do not submit** | exactly three rows (Bid / Fee / Total), Total strongest with its hairline, tabular digits aligned, and the whole-listing amount | none | data-path |
| 14 | The bid screen's commitment copy and the bid-vs-buy-now wording | the resolver's own wording — "You can place a bid instead." only where a bid is actually offered | none | device-rendered |
| 15 | Tickets — the **empty state** (this account has none) | the real Tickets RPC answers on the build, and the empty state reads in both appearances | none | **data-path** (this is the D-8 device step) |
| 16 | Tickets — **not performable on build 23.** The sample-fixture toggle is gated on `__DEV__`, which is false in an EAS `preview` build, so the sample-data caveat cannot be reached on the device at all. Its ink fix (it flips with the fill instead of staying black on Daylight's dark amber) has **harness evidence only**, and that is the whole of it | n/a | — |
| 17 | Orders / My listings — the buyer's existing rows (42 payments, 25 transfers, 6 disputed) | boards render from real rows for a real account | none | **data-path** |
| 18 | Transfer **receive** on the pending row `92ee5156` and the seller_sent row `8f59d37e` — including the seller's proof screenshot | letterbox bars behind the photo are dark, not near-white; the countdown box and its copy read in both | none | **data-path** |
| 19 | Transfer **send** on the same rows (sign in as the DV seller `2f5844b4` — note this registers the push token again for that account) | the seller boards and the marked-sent body (F-28) | **SERVER RECORD:** a second `push_tokens` row for the seller account | **data-path** |
| 20 | Transfer receive **and** send on the four **reversed** rows `e6941c3f`, `b640737b`, `acbfd9fe`, `ddeb0d69` | the reversed boards on **real** data, both roles — "Order closed" with the pending line and never a refund figure, since each payment is `succeeded` with a NULL refund amount | none | **data-path** |

## 4 · Large text and narrow width — no records created

| # | Step | Proves | Writes | Evidence |
|---|---|---|---|---|
| 21 | iOS Settings → Accessibility → Larger Text at maximum, then repeat steps 8, 11, 13, 17, 18 | nothing clips or overlaps at the display cap; the SANDBOX badge keeps its height (it does not scale) | none | device-rendered |
| 22 | Same at the **narrowest** width the phone offers (Display Zoom → Larger Text off, zoomed) | the dock, the bid summary and the transfer boards hold at the narrow width | none | device-rendered |
| 23 | The **dock** across all five tabs, in both appearances, selected and unselected | the glass material, its edge and the selected capsule come from the palette, and both label inks read over the composited dock | none | device-rendered |
| 24 | The **avatar** in the dock and on Profile, with an image and with initials (fallback) | the fallback initial is legible in both appearances, and the avatar is the right account's | none | data-path |

## 5 · The synthetic gallery — rendering only, never retrieval

| # | Step | Proves | Writes | Evidence |
|---|---|---|---|---|
| 25 | Settings → **Sandbox** → "Transfer states (sandbox gallery)" — present only because this is a sandbox build | the entry exists and the route renders | none | device-rendered |
| 26 | Walk all 14 cases in **both** appearances, and again at maximum text size, using the gallery's own System/Light/Dark switch | every transfer-state block renders correctly **from props written in code**, including the states the sandbox has no rows for | none | **synthetic-gallery** |
| 27 | Specifically: **expired**, **reversed**, **held**, the review-deadline line and the refund line, and the cases where `payout_hold_until` or `auto_release_at` is missing | the date line suppresses only itself; held shows the manual-review body | none | **synthetic-gallery** |

**What §5 does not prove.** The sandbox has **no expired and no held transfer rows**. Steps 26–27 therefore
say nothing about whether the app can retrieve those states, whether RLS permits it, or what the real screen
does with a real row. For `expired` and `held` the **data-path is unverified and stays unverified** unless the
owner authorises rows for them. Step 20 is the only place reversed gets data-path evidence.

## 6 · What build 23 does not contain

One commit landed after the build: `24b021a3`. The single rendered difference is the **loading spinner's arc in
the Light appearance** — `#D31212` in build 23, `#FF1A1A` on the branch; both clear the 3:1 bar for a
graphical object. Anything else recorded against a spinner colour should be read against `9c6c9bf4`. Any
further fix that lands after the build goes in this section rather than being assumed present. **No
replacement build is authorised.**

## 7 · Steps that create records — each needs its line approved first

Nothing below has run. Each row names what it writes and which sheet line governs it.

| # | Step | Writes | Governed by |
|---|---|---|---|
| 28 | **Enter checkout** on a live listing (Buy Now) — note that *arriving* on the screen is the write, before any button is pressed | **SERVER RECORD:** a Stripe test-mode PaymentIntent and a pending `payments` row (fresh, or the existing `9f4ab181` reused) | **W2** · sheet D7/D8/P1 |
| 29 | In checkout: the three server-figure rows, "Preparing your total", the price-change case, the sticky bar, then **abandon without paying** | as above; cleanup is A's track C and completes only on a **confirmed** Stripe cancellation | **W2** |
| 30 | The post-charge faces (completed / pending / failed) and the refund face | a charge — not authorised by any current line | **not approved** |
| 31 | **Place a bid** on a live listing | **SERVER RECORD:** one `bids` row, the listing's bid counters, one `bid_received` inbox row. No push dispatch on this sandbox (option (b)) | **W1** · sheet D1/D2 |
| 32 | Outbid toast and the leading-bid state | requires a second bidder — a further write | **W1** + D2 |
| 33 | Confirm receipt, or mark sent, on a real transfer row | **SERVER RECORD:** a state change on a fixture transfer, plus its ledger effects | sheet D3–D6 |
| 34 | Avatar across an **account switch** (D-6) | **SERVER RECORD:** push-token rebind for the second account, and a server-side challenge is possible | sheet D6 |

## 8 · Order of execution

1. Steps 1–2 (install; one push-token row).
2. Steps 3–7 (appearance and startup; device-local only).
3. Steps 8–20 (every reachable surface on real data, both appearances) — **before 2026-09-25 02:01:44Z** while
   the three listings are live.
4. Steps 21–24 (large text, narrow width, dock, avatar).
5. Steps 25–27 (the gallery, recorded as synthetic).
6. **Stop.** Steps 28–34 wait for the owner's approval of A's revision-2 sheet, and for its §0 gate.

A pass recorded from steps 1–27 is a complete **appearance and rendering** pass on real data, with two named
gaps: `expired` and `held` have gallery evidence only, and checkout's own screens are unverified on device
because reaching them creates a payment record.
