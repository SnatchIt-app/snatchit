# B's review of C at `2619b9e1`

**B · 2026-09-24.** Verified in source at C's current commit, not the older snapshot. **Evidence class:
source + computed. Not rendered review, not device verification.**

---

## 1 · Closed — all six, verified

| Item | What I checked | Verdict |
|---|---|---|
| **A-1 / A-2 dock** | No `rgba(` literal remains in `AdaptiveDock.tsx`. Surfaces now read a new `chrome` group: `glass`, `glassEdge`, `glassSelected`, `glassDim`, defined per scheme | **CLOSED.** Measured on the composited dock: **active icon 19.43:1 Midnight / 19.57:1 Daylight**, **inactive 6.25 / 5.27**. The Daylight failures I reported (2.59 and 1.43) are gone |
| **A-3 Sheet grabber** | `:136 backgroundColor: p.border.control` | **CLOSED.** 3.40:1 canvas / 3.10:1 panel — the token I specified, used as specified |
| **A-5 fallback initial** | `EventMedia.tsx:311 color: p.text.muted` | **CLOSED.** **6.28:1 Midnight / 4.80:1 Daylight** — C's comment claims 3:1 large text; it actually clears **4.5:1**, the stricter bar, in both |
| **R-5** | `ListingDetailScreen.tsx:740 offersBid(state)` | **CLOSED, and fixed the right way.** It reads the resolver — the same actions the buttons render — instead of a parallel formula. The comment names the exact case I raised: *"said 'yes' while the viewer held a reservation and the screen showed no bid at all"* |
| **F-28** | The seller `seller_sent` `StateBlock` title no longer duplicates the badge | **CLOSED** |
| **Gallery** | `app/_dev/transfer-states.tsx` + `src/components/transfer/TransferStateBlocks.tsx` | **CLOSED — see §2** |

### The remaining literals are the correct ones

Only three palette-only files still carry literals, and **all three are artwork context**: `EventMedia` (the
four scrim gradient stops), `IconButton.onArt`, `MediaUpload`'s photo overlay. **`AdaptiveDock` and `Sheet`
are clean.**

---

## 2 · The gallery — the constraint that mattered is met

**`TransferStateBlocks.tsx` is imported by `app/transfer/receive/[id].tsx`, `app/transfer/send/[id].tsx`
*and* the gallery.** It is genuinely shared — **not a duplicate mock**, which was the one requirement most
easily failed.

| Requirement | Verified |
|---|---|
| Sandbox-only | `IS_SANDBOX_BUILD` = `ENV_VERDICT.failure === null && appEnv === 'sandbox' && isSandboxHost` — a compile-time verdict, and strict |
| Production cannot render | `:103 if (!(IS_SANDBOX_BUILD \|\| __DEV__)) return <Redirect href="/(tabs)/home" />` |
| Side-effect-free imports | Imports are `expo-router`, `react`, `react-native`, the env guard, `transferState`, theme modules — pinned by a whitelist test |
| Tested entry on the handset | `app/settings/index.tsx:353` renders a **"Sandbox"** section with one row only under the flag. **SG1** asserts the row, its description and that pressing it pushes `/_dev/transfer-states`; **SG2** asserts that with the flag off there is **no row, no section, and no text mentioning it** |
| Date suppression | Corrected: a missing date suppresses **its own line only** |

### One point to note, not a challenge

The guard is `IS_SANDBOX_BUILD || __DEV__`, so the gallery also renders in **any local dev build**, not only
a sandbox one. **Production release builds have `__DEV__` false, so the shipped app is unaffected** — and
`SG2` covers the production case. I read the `|| __DEV__` as deliberate developer convenience and **do not
challenge it**; recording it so nobody later reads "sandbox-only" more narrowly than the code.

---

## 3 · The shared current coverage list — `2619b9e1`

Consumer-reachable only (dev routes and zero-importer components excluded):

| | Files | Change since `016087ea` |
|---|---|---|
| Palette-only | **17** | +1 |
| **Partial — `app/_layout.tsx`** | **1** | unchanged |
| **Unmigrated screens** | **44** | **unchanged** |
| Literal-only | 4 | unchanged |
| No colour access | 26 | |

**C fixed the shared primitives; the screens are untouched.** That is exactly as the owner framed it: **the
screen-level migration is the main remaining implementation task.**

### Work order — the 44, heaviest first

| Accesses | File |
|---|---|
| 58 | `src/screens/CreateListingScreen.tsx` |
| 27 · 27 · 27 | `app/transfer/receive/[id].tsx` · `app/settings/notifications.tsx` · `app/profile/[id].tsx` |
| 26 · 25 | `app/transfer/send/[id].tsx` · `src/screens/checkout/CheckoutNative.tsx` |
| 18 · 16 · 16 | `settings/edit-profile` · `settings/legal` · `report/[type]/[id]` |
| 12 · 11 · 10 | `SellerListingCard` · `listing/edit/[id]` · `bids/BidCard` |
| ≤ 10 | the remaining 33, including `ListingDetailScreen` and `TransactionPanel` — both small |

---

## 4 · What "complete light mode" has to mean for the candidate

**A candidate with 44 unmigrated screens is not complete System/Light/Dark support.** Those screens read
single-valued `v2` colour, so they render **Midnight values on a Daylight canvas** — dark text blocks and
dark panels on white. That is not an exception to be noted; it is the light mode being absent on 44 screens.

**The pre-build completeness gate is therefore: consumer unmigrated = 0 and consumer partial = 0.** Not
"primitives done". **`app/_layout.tsx` is included** — it frames every screen.

**Pre-build completeness and post-build phone verification stay separate.** The gate above is source
evidence. None of it is a device result, and no device result substitutes for it.

---

## 5 · Test-run evidence

**A later passing run does not erase an earlier failure.** Where a suite failed and then passed alone, the
record needs all three: **the failing assertions or timeouts**, **the evidence attributing them to
contention**, and **the isolated final result** — not just the last line. I have run no suite for this
review; my evidence is source reading and arithmetic.
