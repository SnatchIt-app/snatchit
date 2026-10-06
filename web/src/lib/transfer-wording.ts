/**
 * Web marketplace status lines — buyer purchases and seller sales.
 *
 * Pure functions, no server imports, unit-tested in
 * tests/transfer-wording.test.ts. They exist so the wording rules are
 * testable: before this module the strings lived inline in a server
 * component (`actionLine`) and in a `server-only` library (`payoutLabel`),
 * where nothing could assert them.
 *
 * AUTHORITY: PAYMENT_STATE_WORDING_TABLE_20260924.md §2h (ruling, A,
 * 2026-09-25), with §2a-§2d and §2i for the expired/reversed cells. The
 * rules are the app's; only the surface differs.
 *
 * THE RULE THESE FUNCTIONS EXIST TO ENFORCE — three separate facts, never
 * derived from one another:
 *   Order  = transfers.status
 *   Refund = payments.* (NOT read on these surfaces)
 *   Payout = transfers.payout_released_at, with status <> 'reversed'
 *
 * So: no string containing "refund" may be reachable from a path whose only
 * input is transfer.status (§2h acceptance criterion 1). Neither of these
 * surfaces reads the payment row, so neither makes a refund statement at all.
 *
 * Columns read here all predate migration 075 (011, 039, 065) and are in the
 * recorded production ledger, so nothing selected here can 400 on production
 * (criterion 8).
 */

export type WordingTransferStatus =
  | "pending"
  | "seller_sent"
  | "buyer_confirmed"
  | "disputed"
  | "expired"
  | "auto_released"
  | "reversed";

/** 065 writes exactly these three values into transfers.dispute_resolution. */
export const DISPUTE_RESOLUTIONS = [
  "resolved_buyer_refunded",
  "resolved_partial_refund",
  "resolved_seller_paid",
] as const;

export type Line = { text: string; urgent: boolean };

/**
 * Timestamps are rendered Miami-local, the same product definition
 * format.ts states for event dates. Fixed zone, never the runner's or the
 * server's — so the string is the same wherever it is rendered, and the
 * tests do not depend on TZ.
 */
const DISPLAY_TIME_ZONE = "America/New_York";

const DATE_TIME = new Intl.DateTimeFormat("en-US", {
  timeZone: DISPLAY_TIME_ZONE,
  month: "short",
  day: "numeric",
  hour: "numeric",
  minute: "2-digit",
});

/** "2026-09-24T20:31:03Z" -> "Sep 24, 4:31 PM". Null/unparseable -> null. */
export function fmtMoment(iso: string | null | undefined): string | null {
  if (!iso) return null;
  const t = new Date(iso).getTime();
  if (!Number.isFinite(t)) return null;
  return DATE_TIME.format(new Date(t)).replace(" at ", ", ");
}

// ─── Buyer: /account/purchases ────────────────────────────────────────────

export type BuyerLineInput = {
  status: WordingTransferStatus;
  buyer_confirmed_at: string | null;
  dispute_resolved_at: string | null;
  dispute_resolution: string | null;
  delivery_email: string | null;
  delivery_phone: string | null;
};

/**
 * The buyer's one-line state. Says nothing about money: this page does not
 * read the payment row, so a refund fact is not available to it (§2a, §2c).
 */
export function buyerPurchaseLine(t: BuyerLineInput): Line {
  switch (t.status) {
    case "pending":
      return !t.delivery_email && !t.delivery_phone
        ? { text: "Add your delivery info so the seller can send", urgent: true }
        : { text: "Waiting for the seller to send", urgent: false };

    case "seller_sent":
      return { text: "Seller sent — confirm you received them", urgent: true };

    // W-2. The old line ("Disputed — support is reviewing") asserted a human
    // activity the row does not record, and rendered a decided dispute as
    // still open. Decided: state the decision and nothing else — a decision
    // is not a refund and not a payout (§2i).
    case "disputed":
      if (!t.dispute_resolved_at) {
        return {
          text: "Issue reported — the seller's payout is frozen until this is resolved.",
          urgent: false,
        };
      }
      if (t.dispute_resolution === "resolved_buyer_refunded") {
        return { text: "Resolved in your favour", urgent: false };
      }
      if (t.dispute_resolution === "resolved_partial_refund") {
        return { text: "Resolved", urgent: false };
      }
      if (t.dispute_resolution === "resolved_seller_paid") {
        return { text: "Resolved in the seller's favour", urgent: false };
      }
      return { text: "Resolved", urgent: false };

    // W-4. 'buyer_confirmed' is also the status a seller-win decision leaves
    // behind, with buyer_confirmed_at NULL (148). "Confirmed" requires the
    // confirmation record itself.
    case "buyer_confirmed":
      if (t.buyer_confirmed_at) return { text: "Confirmed", urgent: false };
      if (t.dispute_resolution === "resolved_seller_paid") {
        return { text: "Resolved in the seller's favour", urgent: false };
      }
      // Confirmed status with neither a confirmation record nor a seller-win
      // decision. Ruled by A 2026-10-05: say that the order is closed and
      // nothing more. The badge reads "Closed" for the same cell.
      return { text: "Order closed", urgent: false };

    // W-3. The buyer confirmed nothing here; the server released on a timer.
    case "auto_released":
      return { text: "Released", urgent: false };

    // W-1a. "Expired — refunded in full" is withdrawn: an expiry is not a
    // refund, and this page cannot see the payment row.
    case "expired":
      return { text: "Order expired — the seller didn't send the tickets in time.", urgent: false };

    // §2c: 'reversed' is the SELLER's payout event. It is not a buyer money
    // fact, and nothing about the buyer's position may be derived from it.
    case "reversed":
      return { text: "", urgent: false };

    default:
      return { text: "", urgent: false };
  }
}

// ─── Seller: /account/sales ───────────────────────────────────────────────

export type SellerLineInput = {
  status: WordingTransferStatus;
  dispute_resolved_at: string | null;
  dispute_resolution: string | null;
  payout_released_at: string | null;
  // optional so an OrderRowInput (which the panels and the badge use) is
  // assignable here without a second adapter
  payout_review_status?: string | null;
  payout_hold_until?: string | null;
  auto_release_at?: string | null;
};

/**
 * The seller's payout line, in §2h's order of precedence. The order is the
 * safety property: 'reversed' and an open dispute both outrank
 * payout_released_at, which a reversed row still carries (§2d).
 */
export function sellerPayoutLine(s: SellerLineInput): Line {
  // 1. W-5. A reversed row keeps payout_released_at and stripe_transfer_id as
  //    history, so it LOOKS paid out unless status is checked first (§2d).
  if (s.status === "reversed") return { text: "Payout reversed", urgent: true };

  // 2-3. An open dispute, then the decision. "On hold" is withdrawn: the
  //      payout is frozen, and no copy asserts who is reviewing it.
  if (s.status === "disputed") {
    if (!s.dispute_resolved_at) {
      return { text: "Payout frozen — the buyer reported an issue", urgent: true };
    }
    if (
      s.dispute_resolution === "resolved_buyer_refunded" ||
      s.dispute_resolution === "resolved_partial_refund"
    ) {
      return { text: "Resolved for the buyer — no payout for this order", urgent: false };
    }
    // A seller-win decision is a decision, never payout evidence (§2i). If a
    // payout followed, it shows below from payout_released_at.
    if (s.payout_released_at) return { text: "Payout released", urgent: false };
    return { text: "Resolved in your favour — payout pending", urgent: false };
  }

  // 4. W-1b. "Expired — buyer refunded" is withdrawn: the seller's row does
  //    not record the buyer's refund, and the two are separate facts (§2b).
  if (s.status === "expired") {
    return { text: "Order expired — no payout for this order", urgent: false };
  }

  // 5.
  if (s.status === "pending") return { text: "Send the tickets", urgent: true };

  // 6. W-6. Payout evidence. "Paid out" is withdrawn in favour of "Payout
  //    released": we observe the transfer to the connected account, never the
  //    money arriving at a bank (§2i, "never received").
  if (s.payout_released_at) return { text: "Payout released", urgent: false };

  // 7.
  if (s.payout_review_status === "manual_review") {
    return { text: "Payout under review", urgent: false };
  }

  // 8. "until after the event" is withdrawn — the hold ends at a stored time,
  //    and when none is stored no end may be implied.
  if (s.payout_review_status === "held") {
    const until = fmtMoment(s.payout_hold_until ?? null);
    return { text: until ? `Payout held until ${until}` : "Payout held", urgent: false };
  }

  // 9. §2e: a scheduled server time, stated whether or not it has passed.
  //    Never a countdown and never a device-clock branch.
  if (s.status === "seller_sent") {
    const at = fmtMoment(s.auto_release_at ?? null);
    return { text: at ? `Release decision at ${at}` : "", urgent: false };
  }

  // 10. Released by decision, but no payout recorded yet.
  if (s.status === "buyer_confirmed" || s.status === "auto_released") {
    return { text: "Release approved — payout pending", urgent: false };
  }

  return { text: "", urgent: false };
}

// ─── Shared row shape for the panels and the badge ───────────────────────

export type OrderRowInput = {
  status: WordingTransferStatus;
  buyer_confirmed_at: string | null;
  dispute_resolved_at: string | null;
  dispute_resolution: string | null;
  payout_released_at: string | null;
  payout_review_status?: string | null;
  payout_hold_until?: string | null;
  auto_release_at?: string | null;
};

/** §2i: payout evidence, for any audience. `reversed` takes precedence. */
export function hasPayoutEvidence(r: { status: WordingTransferStatus; payout_released_at: string | null }): boolean {
  return r.status !== "reversed" && !!r.payout_released_at;
}

function disputeDecided(r: OrderRowInput): boolean {
  return !!r.dispute_resolved_at;
}

// ─── Status badge ─────────────────────────────────────────────────────────

/**
 * The badge took only `status`, so it asserted things the status does not
 * establish: "Transfer Complete" for a seller-win that no buyer confirmed,
 * "Payout Released" for `auto_released` (a release DECISION, never payout
 * evidence — §2i), "Payment Reversed" for the seller's payout reversal
 * (§2c: not a buyer money fact), and "Disputed" for a decided dispute
 * (criterion 6). It now reads the same row the lines do.
 */
export function transferBadgeLabel(r: OrderRowInput): string {
  switch (r.status) {
    case "pending":
      return "Transfer Pending";
    case "seller_sent":
      return "Transfer Sent";
    case "buyer_confirmed":
      // Only a confirmation record makes this complete. A seller-win and the
      // unruled no-record cell both read "Closed" (A's ruling, 2026-10-05).
      return r.buyer_confirmed_at ? "Transfer Complete" : "Closed";
    case "disputed":
      return disputeDecided(r) ? "Dispute Resolved" : "Disputed";
    case "expired":
      return "Transfer Expired";
    case "auto_released":
      return "Released";
    case "reversed":
      return "Payout Reversed";
    default:
      return "";
  }
}

// ─── Order-state alerts on the two transfer screens ──────────────────────

export type Alert = { tone: "success" | "error"; text: string } | null;

/** Buyer's terminal-state alert on /transfer/receive. */
export function buyerStateAlert(r: OrderRowInput): Alert {
  if (r.status === "buyer_confirmed" || r.status === "auto_released") {
    if (r.status === "auto_released" || r.buyer_confirmed_at) {
      return { tone: "success", text: "Transfer complete. Enjoy the show." };
    }
    if (r.dispute_resolution === "resolved_seller_paid") {
      return { tone: "success", text: "The dispute was resolved in the seller's favour." };
    }
    return { tone: "success", text: "This order is closed." };
  }

  if (r.status === "disputed") {
    // W-4/W-6 (A's ids): no asserted review process, no SLA, and a decided
    // dispute never renders as open.
    if (!disputeDecided(r)) {
      return {
        tone: "error",
        text: "Issue reported. The seller's payout is frozen until this is resolved.",
      };
    }
    if (r.dispute_resolution === "resolved_buyer_refunded") {
      return { tone: "success", text: "Resolved in your favour." };
    }
    if (r.dispute_resolution === "resolved_partial_refund") {
      return { tone: "success", text: "Resolved." };
    }
    if (r.dispute_resolution === "resolved_seller_paid") {
      return { tone: "error", text: "The dispute was resolved in the seller's favour." };
    }
    return { tone: "success", text: "Resolved." };
  }

  // W-1c. "cancelled and refunded in full" asserted a refund from the status
  // alone; this panel does not read the payment row.
  if (r.status === "expired") {
    return {
      tone: "error",
      text: "The seller didn't send the tickets in time, so this order was cancelled.",
    };
  }

  return null;
}

/** Seller's terminal-state alert on /transfer/send. */
export function sellerStateAlert(r: OrderRowInput): Alert {
  if (r.status === "buyer_confirmed" || r.status === "auto_released") {
    if (hasPayoutEvidence(r)) {
      return { tone: "success", text: "Transfer complete and payout released." };
    }
    return {
      tone: "success",
      text: "Transfer complete. No payout has been recorded yet — make sure payouts are set up in Settings.",
    };
  }

  if (r.status === "disputed") {
    if (!disputeDecided(r)) {
      return {
        tone: "error",
        text: "The buyer reported a problem. Your payout is frozen until this is resolved.",
      };
    }
    if (
      r.dispute_resolution === "resolved_buyer_refunded" ||
      r.dispute_resolution === "resolved_partial_refund"
    ) {
      return { tone: "error", text: "Resolved for the buyer — no payout for this order." };
    }
    if (hasPayoutEvidence(r)) {
      return { tone: "success", text: "Resolved in your favour. Payout released." };
    }
    return { tone: "success", text: "Resolved in your favour — payout pending." };
  }

  // W-1d. The seller's row does not record the buyer's refund (§2b).
  if (r.status === "expired") {
    return {
      tone: "error",
      text: "The 24-hour window passed without a transfer, so this order was cancelled. No payout for this order.",
    };
  }

  if (r.status === "reversed") {
    return {
      tone: "error",
      text: "A reversal was recorded on this order's payout. Contact support for details.",
    };
  }

  return null;
}

/**
 * The seller's payout paragraph while `seller_sent`.
 *
 * §2e, ruling 2026-09-24 20:56Z: never "The buyer review window has passed",
 * and no branch on the device clock or on a countdown. The window closes by a
 * status change — `apply_auto_release` or a buyer confirmation — not by the
 * clock, and `buyer_dispute_transfer` accepts a report while `seller_sent`
 * whatever the time. So the line states the scheduled server time and stays
 * true after it passes.
 */
export function sellerPayoutParagraph(r: OrderRowInput): string {
  if (r.payout_review_status === "manual_review") {
    return "This payout is under manual review. Contact support@snatchitapp.com if you have questions.";
  }
  if (r.payout_review_status === "held") {
    const until = fmtMoment(r.payout_hold_until ?? null);
    return until
      ? `Funds are held until ${until} as a standard protection.`
      : "Funds are held as a standard protection.";
  }
  const at = fmtMoment(r.auto_release_at ?? null);
  return at
    ? `Release decision at ${at}. Your payout releases then — sooner if the buyer confirms.`
    : "Your payout releases once the buyer confirms, or at the scheduled release decision.";
}
