# V3 Package 4 — orders, transfers, disputes and support

**B → C · 2026-09-22.** Read at release source `5b255838`, cross-checked on `v3/midnight-app` @ `31819593`.
No payment, payout, refund, transfer-transition or dispute rule is changed.

**Artifacts:** `pkg4-send-{clean,pending,seller_sent,expired}.png` · `pkg4-transfer-matrix.png` ·
`pkg4-dispute-support.png`. The buyer's order screen was approved earlier
(`midnight-order-{clean,annotated}.png`, `midnight-order-unreachable.png`).

---

## 1 · The transfer state matrix — the completeness check for this flow

**The DB constraint allows seven statuses; the shared vocabulary type covers five.** The matrix board shows
all 7 × 2 roles and exactly what each renders *today*, verified in the render path rather than inferred from
the type.

| Status | Seller | Buyer |
|---|---|---|
| `pending` | countdown / "checking" / "still open when last checked" + evidence + Mark as sent | "The seller has not marked the tickets as sent yet." + delivery gate |
| `seller_sent` | "Marked as sent" + **4 payout states** | "…that is the seller's update, not a confirmation." + proof + confirm / dispute |
| `buyer_confirmed` | 2 variants, **gated on `payout_released_at`** | "Tickets received." |
| `auto_released` | "…passed without a dispute. Your payout has been released." | **gated on `payout_released_at`** |
| `disputed` | "…payout is on hold pending review." | "…typically reviews within 24 hours." |
| `expired` | ✅ **"Order expired — don't transfer the tickets for this order."** | 🚫 **nothing renders** |
| `reversed` | 🚫 **nothing renders** | 🚫 **nothing renders** |

> **New sub-finding, verified this round — F-17c.** I previously reported the seller as covered for both
> statuses. `sellerWindowView` handles **only `expired`**; for `reversed` it returns `{ kind: 'none' }`, and the
> send screen has status blocks for `pending`, `seller_sent`, `buyer_confirmed`, `auto_released` and `disputed`
> only. **So `reversed` renders nothing for the seller either.**

**The three read outcomes are already distinct and must stay that way:** `offline` (auto-retrying),
`not_found` (**only** a PostgREST no-row answer supports "Transfer not found") and `unavailable` (every other
failure → the neutral error state). `transferReadOutcome` enforces this and the buyer screen already branches
on `unavailable`. **A failed read is never "not found."**

### What the blocked cells wait on

- **A** — what `expired` and `reversed` actually establish about an order; whether any refund fact is readable
  on the transfer row; whether the two statuses can carry different payment outcomes.
- **C** — whether either status is reachable in practice, what data the screen already holds, the render path.
- **B** — the explanation and recovery route, written from those facts.

**Drafted, not adopted.** The draft states only what the status establishes, keeps refund status and amount
separate, says payment cannot be confirmed there, and offers the shipped support route. **It does not say
"refunded", "handled automatically", an amount, a date, or what happens next.** Displaying a partial refund
elsewhere in the app does **not** mean the system automatically resolves partial-refund obligations — those are
different facts and the design never conflates them.

---

## 2 · Send transfer (seller)

**`pending`** — destination, send window (amber, relative), provider steps, evidence upload, the shipped
commitment sentence, and **Mark as sent**. Both the screenshot and the explicit statement are required first;
that gate is shipped.

**"Mark as sent" is a report, not a delivery**, and the wording never becomes "delivered". **Seven outcomes**
follow it, including an explicit third state — *"Not confirmed yet — we couldn't confirm this transfer was
marked as sent. Pull down to refresh before trying again."* That is the action-sent-but-result-unknown case,
and it already exists. Preserve it.

**`seller_sent`** — "Marked as sent", then **four payout states**, each the shipped sentence: window open ·
window passed · held · manual review. **None states a date on which money arrives**, and "releases" is always
conditional on review.

**`expired`** — the shipped server-first copy, plus a badge that is **a word** rather than the lowercase
`default:` label, and a route to support. The words already exist in `TransferStatusBadge.tsx`, which nothing
imports (**F-18**) — a copy fix, not a new capability. **No payment claim is made in this state at all.**

---

## 3 · Disputes and support — what the product can actually do

**One transfer-dispute path exists:** the buyer's "I haven't received them", guarded by the shipped dialog that
states both consequences — *"This will freeze the transfer and notify support."* — before anything happens.
The result is *"Reported — the transfer has been flagged. Support will review."*

**There is no dispute-status screen, no evidence upload on a dispute, and no way for the seller to respond
in-app.** None are designed here, because designing them would be proposing capabilities.

**The report form** (`/report/[type]/[id]`, listing or user only): shipped reason sets, a 1000-character notes
counter, Submit **disabled until a reason is picked** — an honest disabled control, since there is nothing to
submit — and the shipped discard guard. Success says *"we review reports within 24 hours"*, which is the
shipped sentence, not a new promise.

**Support** is `/settings/support`: three FAQ items and a `mailto:`. No chat, no ticketing, no status. It is the
destination every "Get help" in this package points at **because it is the only one that exists**. Its one
timing claim — *"We aim to respond within 1 to 2 business days"* — is about a reply, not about money.

---

## 4 · The buyer's review deadline

Designed, with the honesty contract fixed and the verification assigned:

> **"Your confirmation is needed by {date}"** · beneath it: *"After that the review window closes."*

**It is not a payout guarantee** and carries nothing about payout timing. **C verifies before implementation:**
the authoritative field (`auto_release_at` is absent from the buyer's select list today — **F-22**), which
statuses may show it, what happens when the value is null or unreadable (the row is **omitted** — no
placeholder date, no "soon"), and refresh behaviour.

---

## 5 · Implementation criteria

1. All seven statuses have a defined rendering for both roles, or are explicitly blocked. **None may fall to a
   lowercase `default:` label.**
2. `offline` / `not_found` / `unavailable` stay distinct; a failed read never claims "not found".
3. The seven mark-as-sent outcomes survive, including "Not confirmed yet".
4. The four payout states survive verbatim; none gains a date.
5. `payout_released_at` still gates every money sentence on both roles.
6. "Marked as sent" is never rendered as "delivered"; the buyer's confirmation stays a separate fact.
7. The dispute dialog keeps both stated consequences and adds no outcome or timeline.
8. Submit on the report form stays disabled until a reason is chosen; the discard guard survives.
9. The review-deadline row is omitted entirely when the field is unavailable.
10. **No new capability** — no dispute status, no seller response, no refund display, no caching.
11. Verified at the largest text size, narrowest width, with a 66-character name and a missing proof image.
12. `typecheck` · `lint` · `test` green; real screenshots beside the boards.

## 6 · Findings touching this flow

**F-17b** buyer sees nothing on `expired`/`reversed` · **F-17c** *(new)* seller sees nothing on `reversed` ·
**F-18** `TransferStatusBadge` never imported · **F-20** failed proof URL is silent · **F-21** raw PostgREST
text reaches the buyer · **F-22** buyer never sees the auto-release deadline · **F-23** `send-push` ignores
notification preferences · **F-24** unknown report type silently becomes a listing report.

All ① present in the release source and on C's branch. **None is fixed by this package.**
