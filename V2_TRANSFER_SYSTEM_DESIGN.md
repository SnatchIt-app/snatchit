# SnatchIt V1 → V2 Ticket Transfer System Design

**Generated:** 2026-04-02 | **Status:** Actionable Protocol Spec | **Audience:** Engineering + Product

---

## SECTION 1 — V1 Transfer Flows (No API Integration)

### 1.1 Seller Listing Flow

**Current state:** Sellers create listings with `event_name`, `venue`, `ticket_type`, `quantity`, `transfer_method` (mobile_transfer | email). No proof of ownership.

**V1 additions to the listing flow:**

1. **Platform Selection (NEW):** Add `ticket_platform` field (enum: `dice`, `eventbrite`, `posh`, `axs`, `ticketmaster`, `other`). Seller selects during listing creation. This drives the Platform Instruction Engine (Section 3).

2. **Proof of Ownership Upload (NEW):** After entering ticket details, seller must upload proof of ownership before the listing goes live.
   - Accepted: screenshot of ticket in app, confirmation email screenshot, order confirmation page
   - Store as image in `auction-media` bucket under `{listing_id}/proof/`
   - Path saved to new `proof_of_ownership_path` column on `listings`
   - Displayed to admins only (never shown to buyers)
   - **V1 enforcement:** Required field — listing cannot be created without it. Frontend blocks submission if missing.

3. **Delivery Info Prompt (NEW):** At listing creation, show a callout: "After your ticket sells, you'll need to transfer it within 24 hours. Make sure you know how to transfer on {platform}." Link to platform-specific instructions (Section 3).

4. **Seller Commitment Checkbox (NEW):** Before publishing, seller checks: "I confirm I own these tickets and will transfer them within 24 hours of sale." Stored as `seller_commitment_accepted_at` timestamp on the listing.

**Listing creation flow (updated):**
```
Event Details → Ticket Details → Platform Selection → Proof Upload → Pricing → Commitment Checkbox → Publish
```

### 1.2 Buyer Purchase Flow

**Current state:** Buyer pays via Stripe → transfer row created (pending) → 24h expiry clock starts. Checkout shows "Check your email for transfer instructions."

**V1 additions:**

1. **Delivery Info Collection (NEW):** After payment succeeds (in checkout success state), prompt buyer to enter delivery details:
   - If `transfer_method === 'email'`: collect buyer's email for ticket transfer (may differ from account email)
   - If `transfer_method === 'mobile_transfer'`: collect buyer's phone number OR the email associated with their ticketing platform account
   - Store on new `delivery_email` and `delivery_phone` columns on `transfers` table
   - **UX:** "The seller needs your info to send the tickets. Where should they send them?"

2. **Post-Purchase Status Screen (NEW):** After checkout, redirect to a dedicated transfer tracking screen (revive and refactor `app/transfer/receive/[id].tsx`):
   - Shows transfer status (pending → seller_sent → buyer_confirmed)
   - Shows countdown timer (24h for seller to send)
   - Shows platform-specific receiving instructions (Section 3)
   - Shows buyer delivery info (editable until seller marks as sent)

### 1.3 Platform-Specific Transfer Instructions

See Section 3 (Platform Instruction Engine) for the full design. In the transfer flow:

- **Seller sees:** Step-by-step instructions for their platform (e.g., "Open Dice app → My Tickets → Select event → Transfer → Enter buyer email")
- **Buyer sees:** Step-by-step instructions for receiving on their platform (e.g., "Check your email for a transfer from Dice → Accept transfer → Ticket appears in your Dice app")

### 1.4 Seller "Mark as Sent" UX

**Current state:** Single "Mark as Sent" button on ListingDetailScreen. No evidence required.

**V1 enhancements:**

1. **Transfer Evidence Upload (NEW):** Before marking as sent, seller must upload proof of transfer:
   - Screenshot of transfer confirmation in the ticketing app
   - Screenshot of email sent with ticket
   - Store in `auction-media` bucket under `{listing_id}/transfer-evidence/`
   - Path saved to new `transfer_evidence_path` column on `transfers`

2. **Dedicated Send Screen (NEW):** Revive `app/transfer/send/[id].tsx`:
   - Show buyer's delivery info (email/phone they provided)
   - Show platform-specific sending instructions
   - Upload transfer evidence
   - Confirmation: "I have transferred the ticket(s) to the buyer" → tap "Mark as Sent"
   - Calls existing `mark_transfer_sent` RPC (extend to accept evidence path)

3. **Post-Send State:** After marking sent, show:
   - "Waiting for buyer to confirm receipt"
   - Auto-release countdown (72h)
   - Warning: "If the buyer reports an issue, your payout will be held for review"

### 1.5 Buyer Confirmation UX

**Current state:** "Confirm Received" and "Report Issue" buttons on ListingDetailScreen.

**V1 enhancements:**

1. **Dedicated Receive Screen (NEW):** Revive `app/transfer/receive/[id].tsx`:
   - Show platform-specific receiving instructions
   - Checklist: "Did you receive the ticket? Can you see it in your {platform} app?"
   - Two clear actions:
     - **"I Got My Tickets"** → calls `confirm-and-release` edge function → payout released
     - **"I Haven't Received Them"** → opens dispute flow

2. **Confirmation Prompt:** Before confirming, show: "By confirming, you release payment to the seller. Only confirm if you can see the tickets in your {platform} account."

### 1.6 Dispute UX

**Current state:** "Report Issue" button calls `buyer_dispute_transfer` RPC. Sets status to `disputed`. No further workflow.

**V1 enhancements:**

1. **Dispute Reason Selection (NEW):** Buyer selects from:
   - `never_received` — "I never received the tickets"
   - `wrong_tickets` — "I received the wrong tickets"
   - `invalid_tickets` — "The tickets don't work / are invalid"
   - `partial_delivery` — "I only received some of the tickets"
   - Store as `dispute_reason` enum on `transfers`

2. **Dispute Evidence Upload (NEW):** Buyer can upload screenshots showing:
   - Empty inbox (for `never_received`)
   - Wrong ticket details (for `wrong_tickets`)
   - Error screens from ticketing app (for `invalid_tickets`)
   - Store in `auction-media` bucket under `{listing_id}/dispute-evidence/`
   - Path saved to `dispute_evidence_path` on `transfers`

3. **Dispute Notes (NEW):** Free-text field for buyer to describe the issue. Stored as `dispute_notes` on `transfers`.

4. **Post-Dispute State:**
   - Buyer sees: "Your issue has been reported. Our team will review within 24 hours. Your payment is protected."
   - Seller sees: "The buyer has reported an issue with the transfer. Your payout is on hold pending review."
   - Admin sees: All evidence from both sides (proof of ownership, transfer evidence, dispute evidence, dispute reason/notes)

5. **Admin Resolution (V1 manual):** Admin reviews evidence and either:
   - Releases payout to seller (calls a new admin RPC)
   - Issues refund to buyer (triggers Stripe refund)
   - Store resolution as `dispute_resolution` enum: `resolved_seller_paid`, `resolved_buyer_refunded`, `resolved_partial_refund`
   - Store `dispute_resolved_at` timestamp and `dispute_resolved_by` (admin user ID)

---

## SECTION 2 — Data Model

### 2.1 Listings Table Changes

```sql
-- New columns on listings
ALTER TABLE listings
  ADD COLUMN ticket_platform TEXT NOT NULL DEFAULT 'other'
    CHECK (ticket_platform IN ('dice', 'eventbrite', 'posh', 'axs', 'ticketmaster', 'other')),
  ADD COLUMN proof_of_ownership_path TEXT,
  ADD COLUMN seller_commitment_accepted_at TIMESTAMPTZ;
```

**Notes:**
- `ticket_platform` is required. Default `'other'` covers unknown platforms.
- `proof_of_ownership_path` stores the storage bucket path (e.g., `{listing_id}/proof/screenshot.jpg`).
- `seller_commitment_accepted_at` is set when seller checks the commitment box. NULL = not accepted.

### 2.2 Transfers Table Changes

```sql
-- New columns on transfers
ALTER TABLE transfers
  -- Delivery info (buyer provides post-purchase)
  ADD COLUMN delivery_email TEXT,
  ADD COLUMN delivery_phone TEXT,

  -- Transfer evidence (seller provides when marking as sent)
  ADD COLUMN transfer_evidence_path TEXT,

  -- Dispute details
  ADD COLUMN dispute_reason TEXT
    CHECK (dispute_reason IN ('never_received', 'wrong_tickets', 'invalid_tickets', 'partial_delivery')),
  ADD COLUMN dispute_evidence_path TEXT,
  ADD COLUMN dispute_notes TEXT,

  -- Dispute resolution (admin action)
  ADD COLUMN dispute_resolution TEXT
    CHECK (dispute_resolution IN ('resolved_seller_paid', 'resolved_buyer_refunded', 'resolved_partial_refund')),
  ADD COLUMN dispute_resolved_at TIMESTAMPTZ,
  ADD COLUMN dispute_resolved_by UUID REFERENCES auth.users(id);
```

### 2.3 How Delivery Details Are Stored

Delivery details live on the `transfers` row (not on profiles or listings) because:
- A buyer might use different emails for different ticket platforms
- Delivery info is per-transaction, not per-user
- Keeps the data lifecycle tied to the transfer

**Flow:**
1. Payment succeeds → transfer row created with `delivery_email = NULL`, `delivery_phone = NULL`
2. Buyer enters delivery info on the post-purchase screen
3. Client calls a new RPC: `set_transfer_delivery_info(p_transfer_id, p_email, p_phone)`
4. RPC validates buyer ownership and transfer is still `pending`
5. Seller can see delivery info once provided (visible on the send screen)

```sql
CREATE OR REPLACE FUNCTION set_transfer_delivery_info(
  p_transfer_id UUID,
  p_delivery_email TEXT DEFAULT NULL,
  p_delivery_phone TEXT DEFAULT NULL
) RETURNS VOID AS $$
BEGIN
  UPDATE transfers
  SET delivery_email = COALESCE(p_delivery_email, delivery_email),
      delivery_phone = COALESCE(p_delivery_phone, delivery_phone)
  WHERE id = p_transfer_id
    AND buyer_id = auth.uid()
    AND status = 'pending';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transfer not found, not yours, or no longer pending';
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

### 2.4 How Proof of Ownership Is Stored

- Stored in Supabase Storage (`auction-media` bucket), path: `{listing_id}/proof/{filename}`
- Path reference saved on `listings.proof_of_ownership_path`
- Uploaded during listing creation (before publish)
- **RLS:** Only the seller (uploader) and admins can view. NOT exposed via public listing queries.
- Add a storage policy restricting download to `seller_id` match or admin role.

### 2.5 How Transfer Evidence Is Stored

- Stored in Supabase Storage (`auction-media` bucket), path: `{listing_id}/transfer-evidence/{filename}`
- Path reference saved on `transfers.transfer_evidence_path`
- Uploaded during the "mark as sent" flow
- **RLS:** Visible to buyer, seller, and admins for the relevant transfer.

### 2.6 How Dispute Evidence Is Stored

- Stored in Supabase Storage (`auction-media` bucket), path: `{listing_id}/dispute-evidence/{filename}`
- Path reference saved on `transfers.dispute_evidence_path`
- Uploaded during the dispute flow
- **RLS:** Visible to buyer, seller, and admins for the relevant transfer.

### 2.7 Migration File

Create as `011_v1_transfer_enhancements.sql`:

```sql
-- Migration: V1 Transfer Enhancements
-- Adds platform selection, proof of ownership, delivery info,
-- transfer evidence, and dispute details

-- 1. Listings: platform + proof
ALTER TABLE listings
  ADD COLUMN IF NOT EXISTS ticket_platform TEXT NOT NULL DEFAULT 'other'
    CHECK (ticket_platform IN ('dice', 'eventbrite', 'posh', 'axs', 'ticketmaster', 'other')),
  ADD COLUMN IF NOT EXISTS proof_of_ownership_path TEXT,
  ADD COLUMN IF NOT EXISTS seller_commitment_accepted_at TIMESTAMPTZ;

-- 2. Transfers: delivery info + evidence + dispute details
ALTER TABLE transfers
  ADD COLUMN IF NOT EXISTS delivery_email TEXT,
  ADD COLUMN IF NOT EXISTS delivery_phone TEXT,
  ADD COLUMN IF NOT EXISTS transfer_evidence_path TEXT,
  ADD COLUMN IF NOT EXISTS dispute_reason TEXT
    CHECK (dispute_reason IN ('never_received', 'wrong_tickets', 'invalid_tickets', 'partial_delivery')),
  ADD COLUMN IF NOT EXISTS dispute_evidence_path TEXT,
  ADD COLUMN IF NOT EXISTS dispute_notes TEXT,
  ADD COLUMN IF NOT EXISTS dispute_resolution TEXT
    CHECK (dispute_resolution IN ('resolved_seller_paid', 'resolved_buyer_refunded', 'resolved_partial_refund')),
  ADD COLUMN IF NOT EXISTS dispute_resolved_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS dispute_resolved_by UUID REFERENCES auth.users(id);

-- 3. RPC: Set delivery info
CREATE OR REPLACE FUNCTION set_transfer_delivery_info(
  p_transfer_id UUID,
  p_delivery_email TEXT DEFAULT NULL,
  p_delivery_phone TEXT DEFAULT NULL
) RETURNS VOID AS $$
BEGIN
  UPDATE transfers
  SET delivery_email = COALESCE(p_delivery_email, delivery_email),
      delivery_phone = COALESCE(p_delivery_phone, delivery_phone)
  WHERE id = p_transfer_id
    AND buyer_id = auth.uid()
    AND status = 'pending';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transfer not found, not authorized, or no longer pending';
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. RPC: Update mark_transfer_sent to accept evidence path
CREATE OR REPLACE FUNCTION mark_transfer_sent(
  p_transfer_id UUID,
  p_user_id UUID,
  p_transfer_evidence_path TEXT DEFAULT NULL
) RETURNS VOID AS $$
BEGIN
  UPDATE transfers
  SET status = 'seller_sent',
      seller_sent_at = NOW(),
      auto_release_at = NOW() + INTERVAL '72 hours',
      transfer_evidence_path = COALESCE(p_transfer_evidence_path, transfer_evidence_path)
  WHERE id = p_transfer_id
    AND seller_id = p_user_id
    AND status = 'pending'
  FOR UPDATE SKIP LOCKED;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transfer not found, not authorized, or not in pending state';
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. RPC: Update buyer_dispute_transfer to accept reason + evidence
CREATE OR REPLACE FUNCTION buyer_dispute_transfer(
  p_transfer_id UUID,
  p_user_id UUID,
  p_dispute_reason TEXT DEFAULT NULL,
  p_dispute_evidence_path TEXT DEFAULT NULL,
  p_dispute_notes TEXT DEFAULT NULL
) RETURNS VOID AS $$
BEGIN
  UPDATE transfers
  SET status = 'disputed',
      disputed_at = NOW(),
      dispute_reason = p_dispute_reason,
      dispute_evidence_path = p_dispute_evidence_path,
      dispute_notes = p_dispute_notes
  WHERE id = p_transfer_id
    AND buyer_id = p_user_id
    AND status = 'seller_sent'
  FOR UPDATE SKIP LOCKED;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transfer not found, not authorized, or not in seller_sent state';
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. RPC: Admin resolve dispute
CREATE OR REPLACE FUNCTION admin_resolve_dispute(
  p_transfer_id UUID,
  p_resolution TEXT,
  p_admin_id UUID
) RETURNS VOID AS $$
BEGIN
  IF p_resolution NOT IN ('resolved_seller_paid', 'resolved_buyer_refunded', 'resolved_partial_refund') THEN
    RAISE EXCEPTION 'Invalid resolution type';
  END IF;

  UPDATE transfers
  SET dispute_resolution = p_resolution,
      dispute_resolved_at = NOW(),
      dispute_resolved_by = p_admin_id
  WHERE id = p_transfer_id
    AND status = 'disputed'
  FOR UPDATE SKIP LOCKED;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transfer not found or not in disputed state';
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

### 2.8 Updated TypeScript Types

```typescript
// Add to src/types/index.ts

export type TicketPlatform = 'dice' | 'eventbrite' | 'posh' | 'axs' | 'ticketmaster' | 'other';

export type DisputeReason = 'never_received' | 'wrong_tickets' | 'invalid_tickets' | 'partial_delivery';

export type DisputeResolution = 'resolved_seller_paid' | 'resolved_buyer_refunded' | 'resolved_partial_refund';

// Update Listing type to include:
// ticket_platform: TicketPlatform;
// proof_of_ownership_path: string | null;
// seller_commitment_accepted_at: string | null;

// Update Transfer type (or create one):
export interface Transfer {
  id: string;
  listing_id: string;
  payment_id: string;
  seller_id: string;
  buyer_id: string;
  transfer_method: TransferMethod;
  status: 'pending' | 'seller_sent' | 'buyer_confirmed' | 'disputed' | 'expired' | 'auto_released';
  created_at: string;
  seller_sent_at: string | null;
  buyer_confirmed_at: string | null;
  expires_at: string;
  expired_at: string | null;
  disputed_at: string | null;
  auto_release_at: string | null;
  payout_released_at: string | null;
  stripe_transfer_id: string | null;
  // V1 additions
  delivery_email: string | null;
  delivery_phone: string | null;
  transfer_evidence_path: string | null;
  dispute_reason: DisputeReason | null;
  dispute_evidence_path: string | null;
  dispute_notes: string | null;
  dispute_resolution: DisputeResolution | null;
  dispute_resolved_at: string | null;
  dispute_resolved_by: string | null;
}
```

---

## SECTION 3 — Platform Instruction Engine

### 3.1 Architecture

A JSON-driven instruction system that maps `ticket_platform` to structured step-by-step guides for both seller (sending) and buyer (receiving).

**Why JSON, not database:** Platform instructions change rarely and are read-heavy. A static JSON file shipped with the app avoids database queries and works offline. Update via app release.

### 3.2 Data Structure

Create `src/lib/platformInstructions.ts`:

```typescript
export interface PlatformInstruction {
  platform: TicketPlatform;
  displayName: string;
  icon: string; // emoji or icon name
  transferMethods: TransferMethod[];
  seller: {
    title: string;
    steps: string[];
    tips: string[];
    estimatedTime: string;
    videoUrl?: string;
  };
  buyer: {
    title: string;
    steps: string[];
    tips: string[];
    estimatedTime: string;
  };
  warnings: string[];
}

export const PLATFORM_INSTRUCTIONS: Record<TicketPlatform, PlatformInstruction> = {
  dice: {
    platform: 'dice',
    displayName: 'DICE',
    icon: '🎲',
    transferMethods: ['mobile_transfer'],
    seller: {
      title: 'How to transfer tickets on DICE',
      steps: [
        'Open the DICE app on your phone',
        'Go to "My Tickets" from the bottom menu',
        'Find and tap on the event',
        'Tap "Transfer Ticket"',
        'Enter the buyer\'s email address: {buyer_email}',
        'Confirm the transfer',
        'Take a screenshot of the confirmation',
      ],
      tips: [
        'Make sure you\'re transferring the correct ticket(s)',
        'The buyer must have a DICE account with the email you send to',
        'Transfers usually arrive within a few minutes',
      ],
      estimatedTime: '2-5 minutes',
    },
    buyer: {
      title: 'How to receive tickets on DICE',
      steps: [
        'Make sure you have the DICE app installed',
        'Check that your DICE account uses the email you provided',
        'You\'ll receive a notification when the seller sends your ticket',
        'Open DICE → "My Tickets" to see the transferred ticket',
        'If you don\'t see it, check your email for a transfer link',
      ],
      tips: [
        'If you don\'t have a DICE account, create one with the same email you gave the seller',
        'Transfers typically arrive within minutes',
        'Contact us if you haven\'t received the transfer within 2 hours',
      ],
      estimatedTime: '1-2 minutes to accept',
    },
    warnings: [
      'DICE tickets can only be transferred once',
      'Make sure the email address is correct before transferring',
    ],
  },

  eventbrite: {
    platform: 'eventbrite',
    displayName: 'Eventbrite',
    icon: '🎟️',
    transferMethods: ['email'],
    seller: {
      title: 'How to transfer tickets on Eventbrite',
      steps: [
        'Go to eventbrite.com or open the Eventbrite app',
        'Navigate to "Tickets" or "My Orders"',
        'Find the event and click "Transfer"',
        'Enter the buyer\'s email: {buyer_email}',
        'Add a message (optional)',
        'Click "Transfer"',
        'Screenshot the confirmation page',
      ],
      tips: [
        'Eventbrite sends the buyer a new ticket via email',
        'Your original ticket will be cancelled after transfer',
      ],
      estimatedTime: '3-5 minutes',
    },
    buyer: {
      title: 'How to receive tickets on Eventbrite',
      steps: [
        'Check your email (including spam/promotions) for a transfer notification from Eventbrite',
        'Click "Accept Transfer" in the email',
        'Sign in to or create an Eventbrite account',
        'Your ticket will appear in "My Tickets"',
      ],
      tips: [
        'Check your spam folder if you don\'t see the email',
        'You can also check eventbrite.com → My Tickets',
      ],
      estimatedTime: '1-2 minutes to accept',
    },
    warnings: [
      'Some Eventbrite events do not allow transfers. The seller should verify before listing.',
    ],
  },

  posh: {
    platform: 'posh',
    displayName: 'Posh',
    icon: '✨',
    transferMethods: ['mobile_transfer'],
    seller: {
      title: 'How to transfer tickets on Posh',
      steps: [
        'Open the Posh app',
        'Go to "My Tickets"',
        'Tap on the event',
        'Tap "Send Ticket"',
        'Enter the buyer\'s phone number: {buyer_phone}',
        'Confirm the send',
        'Screenshot the confirmation',
      ],
      tips: [
        'Posh transfers work via phone number, not email',
        'The buyer must have the Posh app installed',
      ],
      estimatedTime: '2-3 minutes',
    },
    buyer: {
      title: 'How to receive tickets on Posh',
      steps: [
        'Install the Posh app if you don\'t have it',
        'Sign up with the phone number you provided',
        'You\'ll see the ticket appear in "My Tickets"',
        'You may also receive a text notification',
      ],
      tips: [
        'Make sure your Posh account is registered with the phone number you gave the seller',
      ],
      estimatedTime: '1 minute to accept',
    },
    warnings: [
      'Posh requires the recipient to have an account with the same phone number',
    ],
  },

  axs: {
    platform: 'axs',
    displayName: 'AXS',
    icon: '🎫',
    transferMethods: ['mobile_transfer', 'email'],
    seller: {
      title: 'How to transfer tickets on AXS',
      steps: [
        'Open the AXS app or go to axs.com',
        'Go to "My Events"',
        'Select the event and tap "Transfer"',
        'Enter the buyer\'s email: {buyer_email}',
        'Confirm the transfer',
        'Screenshot the confirmation',
      ],
      tips: [
        'AXS transfers can be done via app or website',
        'The recipient gets an email to claim the ticket',
      ],
      estimatedTime: '3-5 minutes',
    },
    buyer: {
      title: 'How to receive tickets on AXS',
      steps: [
        'Check your email for a transfer notification from AXS',
        'Click "Accept" in the email',
        'Sign in to or create your AXS account',
        'Ticket appears in "My Events" in the AXS app',
      ],
      tips: [
        'Download the AXS app to access your mobile ticket on event day',
      ],
      estimatedTime: '2-3 minutes',
    },
    warnings: [],
  },

  ticketmaster: {
    platform: 'ticketmaster',
    displayName: 'Ticketmaster',
    icon: '🎪',
    transferMethods: ['mobile_transfer', 'email'],
    seller: {
      title: 'How to transfer tickets on Ticketmaster',
      steps: [
        'Open the Ticketmaster app or go to ticketmaster.com',
        'Go to "My Events"',
        'Tap on the event → "Transfer"',
        'Enter the buyer\'s name and email: {buyer_email}',
        'Confirm the transfer',
        'Screenshot the confirmation',
      ],
      tips: [
        'Some events restrict transfers — verify before listing',
        'Ticketmaster transfers are usually instant',
      ],
      estimatedTime: '2-5 minutes',
    },
    buyer: {
      title: 'How to receive tickets on Ticketmaster',
      steps: [
        'Check your email for a transfer from Ticketmaster',
        'Click "Accept Tickets"',
        'Sign in to your Ticketmaster account (create one if needed)',
        'Tickets appear in "My Events"',
      ],
      tips: [
        'Use the same email address you provided to the seller',
        'Download the Ticketmaster app for mobile tickets',
      ],
      estimatedTime: '1-2 minutes',
    },
    warnings: [
      'Some Ticketmaster events have transfer restrictions',
    ],
  },

  other: {
    platform: 'other',
    displayName: 'Other Platform',
    icon: '📧',
    transferMethods: ['email', 'mobile_transfer'],
    seller: {
      title: 'How to transfer your tickets',
      steps: [
        'Open the app or website where you purchased the tickets',
        'Find the ticket transfer or send option',
        'Enter the buyer\'s contact info as provided',
        'Complete the transfer',
        'Take a screenshot of the confirmation',
      ],
      tips: [
        'If the platform doesn\'t support transfer, contact the event organizer',
      ],
      estimatedTime: '5-10 minutes',
    },
    buyer: {
      title: 'How to receive your tickets',
      steps: [
        'Check your email and phone for a transfer notification',
        'Follow the instructions in the notification to accept',
        'Download any required app for the ticket platform',
      ],
      tips: [
        'Contact the seller via SnatchIt if you haven\'t received anything within 2 hours',
      ],
      estimatedTime: 'Varies',
    },
    warnings: [
      'Transfer process varies by platform. If you have issues, open a dispute.',
    ],
  },
};
```

### 3.3 Instruction Rendering

Create a `PlatformInstructions` component that:
- Receives `platform: TicketPlatform` and `role: 'seller' | 'buyer'`
- Looks up instructions from the JSON map
- Renders step-by-step with numbered steps
- Substitutes `{buyer_email}` and `{buyer_phone}` placeholders with actual delivery info
- Shows warnings in a yellow callout
- Shows tips in a collapsible section

### 3.4 Extensibility

Adding a new platform requires:
1. Add enum value to `ticket_platform` CHECK constraint (migration)
2. Add entry to `PLATFORM_INSTRUCTIONS` map
3. No code changes needed — the instruction engine reads from the map

---

## SECTION 4 — Anti-Fraud System (V1)

### 4.1 Signals We Track

| Signal | Source | Risk Indicator |
|--------|--------|----------------|
| Account age | `profiles.created_at` | New accounts (< 7 days) selling high-value tickets |
| Listing velocity | `listings` count per seller per 24h | More than 5 listings in 24h = suspicious |
| Transfer completion rate | `transfers` where `status = 'buyer_confirmed'` / total | < 50% completion rate over 5+ sales = red flag |
| Dispute rate | `transfers` where `status = 'disputed'` / total | > 20% dispute rate over 5+ sales = red flag |
| Transfer speed | `seller_sent_at - created_at` | Consistently sending within < 1 min = possible auto-confirm fraud |
| Proof of ownership | `listings.proof_of_ownership_path` | NULL or duplicate images across listings |
| Multiple listings same event | `listings` per seller per `event_name + event_date` | > 3 listings for same event = possible double-sell |
| Payout velocity | `transfers.payout_released_at` frequency | Rapid payouts on multiple listings for same event |

### 4.2 How Disputes Are Evaluated

**V1 Manual Process (admin dashboard):**

1. **Dispute filed** → transfer status set to `disputed`, payout frozen.
2. **Evidence review checklist:**
   - Does seller have proof of ownership? (check `proof_of_ownership_path`)
   - Does seller have transfer evidence? (check `transfer_evidence_path`)
   - Does buyer have dispute evidence? (check `dispute_evidence_path`)
   - What is the dispute reason?
   - What is the seller's historical dispute rate?
3. **Decision matrix:**

| Scenario | Evidence | Resolution |
|----------|----------|------------|
| Seller has transfer evidence, buyer has no dispute evidence | Seller likely transferred | `resolved_seller_paid` |
| Buyer shows empty inbox, seller has no transfer evidence | Seller likely didn't send | `resolved_buyer_refunded` |
| Both have evidence, unclear | Escalate to manual review | Hold for 48h, then decide |
| Seller has pattern of disputes | Weight toward buyer | `resolved_buyer_refunded` |
| Buyer has pattern of disputes | Weight toward seller | `resolved_seller_paid` |

4. **Auto-escalation rules:**
   - If seller has > 3 open disputes → freeze all their active listings
   - If seller dispute rate > 30% → suspend seller account
   - If buyer files > 3 disputes in 30 days → flag for review (potential "dispute fraud")

### 4.3 Double-Selling Prevention

**Problem:** A seller lists the same ticket on SnatchIt and another platform, or lists it twice on SnatchIt.

**V1 Mitigations:**

1. **Duplicate detection:** On listing creation, check if the same seller has another active listing with matching `event_name`, `event_date`, and `ticket_type`. If so, show a warning: "You already have a listing for this event. Are you sure you have additional tickets?"

2. **Proof uniqueness check:** Compare `proof_of_ownership_path` image hashes across active listings. If the same image is used for multiple listings, flag for review. (V1: manual check. V2: automated perceptual hash.)

3. **24-hour transfer deadline:** The existing 24h expiry on pending transfers limits the window for double-selling. If a seller can't transfer within 24h, the buyer gets auto-refunded.

4. **Seller commitment:** The checkbox at listing creation ("I confirm I own these tickets") creates a legal record. Combined with proof of ownership, this establishes accountability.

5. **Post-sale listing pause:** After a ticket sells, auto-check if the seller has other active listings for the same event. If so, send a push notification: "You just sold a ticket for {event}. Make sure your other listings for this event have separate tickets."

### 4.4 Detecting Suspicious Sellers

**Automated flags (V1, run on cron or at listing creation):**

| Flag | Trigger | Action |
|------|---------|--------|
| `NEW_SELLER_HIGH_VALUE` | Account < 7 days, listing > $200 | Add review queue, delay payout release by 24h |
| `RAPID_LISTING` | > 5 listings in 24h | Temporarily pause new listings, notify admin |
| `HIGH_DISPUTE_RATE` | > 30% dispute rate (min 5 sales) | Suspend seller, freeze active listings |
| `DUPLICATE_PROOF` | Same proof image across listings | Flag for review |
| `SAME_EVENT_OVERLOAD` | > 3 active listings for same event | Warning to seller, flag for review |
| `INSTANT_MARK_SENT` | Average send time < 2 minutes | Flag (may be marking sent without actually transferring) |

**Implementation:** Create a `seller_flags` table:

```sql
CREATE TABLE seller_flags (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  seller_id UUID NOT NULL REFERENCES auth.users(id),
  flag_type TEXT NOT NULL,
  listing_id UUID REFERENCES listings(id),
  details JSONB,
  resolved BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
```

---

## SECTION 5 — V2 Enhancements

### 5.1 Email Parsing for Transfer Verification

**Concept:** When a seller transfers a ticket via a platform, the buyer often receives an email (e.g., "You've received a ticket transfer from Dice"). If the buyer forwards this email to a SnatchIt verification address, we can parse it to auto-confirm the transfer.

**Architecture:**
1. **Inbound email:** Set up an inbound email address (e.g., `verify@snatchit.app`) using a service like SendGrid Inbound Parse, Mailgun, or Postmark.
2. **Email parser:** Edge function receives forwarded email, extracts:
   - Sender domain (dice.fm, eventbrite.com, etc.) — validates it's from a real platform
   - Event name / ticket details
   - Recipient email (should match buyer's delivery email)
3. **Match to transfer:** Cross-reference parsed data with open `seller_sent` transfers.
4. **Auto-confirm:** If match confidence is high (platform domain verified, event matches, recipient matches), auto-transition to `buyer_confirmed` and release payout.
5. **Fallback:** If match confidence is low, flag for manual review but show buyer "We received your verification — reviewing now."

**V2 Priority:** Medium. Reduces friction for buyer confirmation but requires email infrastructure.

### 5.2 Semi-Automated Confirmation

**Concept:** For platforms where we can observe the transfer status (via email parsing, screenshot OCR, or future webhooks), auto-confirm transfers without buyer action.

**Tiers:**
1. **Tier 1 (Email parsing):** Buyer forwards confirmation email → auto-confirm (see 5.1)
2. **Tier 2 (Screenshot OCR):** Buyer uploads screenshot of received ticket → OCR extracts event name, date, venue → match against transfer → auto-confirm with high confidence
3. **Tier 3 (Future API):** If platforms ever open transfer verification APIs, integrate directly

**V2 Implementation for Tier 2:**
- Use a vision model or OCR service to extract text from buyer's screenshot
- Match extracted event details against the listing data
- If confidence > 90%, auto-confirm. Otherwise, require manual confirmation.

### 5.3 Reputation System

**Seller Reputation Score (visible to buyers):**

| Factor | Weight | Calculation |
|--------|--------|-------------|
| Completion rate | 40% | `confirmed_transfers / total_transfers` |
| Speed score | 20% | Average time from sale to `seller_sent` (faster = better) |
| Dispute rate | 25% | `1 - (disputed_transfers / total_transfers)` (lower disputes = better) |
| Account age | 10% | Log scale, capped at 1 year |
| Proof quality | 5% | Has proof of ownership on all listings |

**Display:** Star rating (1-5) or badge system:
- **"Verified Seller"** — 10+ sales, > 90% completion, < 5% dispute rate
- **"New Seller"** — < 5 sales
- **"Trusted Seller"** — 25+ sales, > 95% completion, 0% dispute rate

**Buyer Reputation (internal, not displayed):**
- Track dispute filing rate
- Flag buyers who consistently file disputes (potential "dispute fraud")
- Used in dispute resolution weighting

### 5.4 Seller Scoring System

**Internal scoring for risk assessment (not displayed to buyers):**

```
seller_risk_score = (
  0.3 * dispute_rate_score +          // 0-100, lower is better
  0.2 * transfer_speed_score +        // 0-100, faster is better
  0.2 * account_age_score +           // 0-100, older is better
  0.15 * listing_quality_score +      // 0-100, proof + commitment + accuracy
  0.15 * volume_score                 // 0-100, more completed sales is better
)
```

**Usage:**
- Score < 30: Auto-hold payouts for 48h (even after buyer confirms)
- Score 30-60: Standard flow
- Score > 60: Eligible for expedited payouts (reduced auto-release from 72h to 48h)
- Score > 80: Eligible for "Trusted Seller" badge

**Recalculation:** Run nightly via cron. Store on a `seller_scores` table:

```sql
CREATE TABLE seller_scores (
  seller_id UUID PRIMARY KEY REFERENCES auth.users(id),
  risk_score NUMERIC NOT NULL DEFAULT 50,
  completion_rate NUMERIC,
  avg_transfer_speed_minutes NUMERIC,
  dispute_rate NUMERIC,
  total_sales INTEGER DEFAULT 0,
  last_calculated_at TIMESTAMPTZ DEFAULT NOW()
);
```

---

## SECTION 6 — UX Copy

### 6.1 Seller Instructions

**Listing creation — platform selection:**
> "Which platform are your tickets on? This helps us give the buyer the right instructions for receiving them."

**Listing creation — proof upload:**
> "Upload a screenshot showing you own these tickets. This could be your ticket in the app, your confirmation email, or your order page. This is only visible to our team — never shown to buyers."

**Listing creation — commitment checkbox:**
> "I confirm I own these tickets and will transfer them to the buyer within 24 hours of sale. I understand that failing to transfer will result in an automatic refund and may affect my seller standing."

**Post-sale — transfer pending:**
> "Your ticket sold! You have 24 hours to transfer it to the buyer. Here's how:"
> [Platform-specific instructions with buyer's delivery info]
> "After you've sent the ticket, upload a screenshot of the confirmation and tap 'Mark as Sent'."

**Post-send — waiting for buyer:**
> "You've marked the ticket as sent. The buyer has 72 hours to confirm they received it. If they don't respond, your payout will be released automatically."

**Dispute received:**
> "The buyer has reported an issue with this transfer. Your payout is on hold while we review. If you transferred the ticket correctly, your transfer evidence will support your case. We'll resolve this within 24 hours."

### 6.2 Buyer Instructions

**Post-purchase — delivery info:**
> "The seller needs to know where to send your tickets. Enter the email (or phone number) associated with your {platform} account."

**Post-purchase — waiting for seller:**
> "The seller has 24 hours to transfer your tickets. We'll notify you as soon as they're sent. Your payment is protected — if the seller doesn't send the tickets, you'll get a full refund automatically."

**Transfer sent — confirm receipt:**
> "The seller says they've sent your tickets! Here's how to check:"
> [Platform-specific receiving instructions]
> "Once you can see the tickets in your {platform} account, tap 'I Got My Tickets' to release payment to the seller."

**Pre-confirmation warning:**
> "Only confirm if you can see the tickets in your {platform} app. By confirming, you release payment to the seller. This cannot be undone."

**Dispute flow:**
> "Sorry to hear you're having trouble. Let us know what happened so we can help:"
> [Reason selection]
> "Upload a screenshot if you can — it helps us resolve things faster. Your payment is protected while we review."

### 6.3 Trust-Building & Fraud-Reducing Warnings

**On every listing page (buyer view):**
> "Protected by SnatchIt Guarantee — your payment is held securely until you confirm you received your tickets. Full refund if the seller doesn't deliver."

**On checkout:**
> "Your payment is protected. The seller won't receive any money until you confirm the tickets were transferred to you."

**On seller profile (new seller):**
> "New seller — first time selling on SnatchIt. All transactions are protected by our guarantee."

**On seller profile (verified):**
> "Verified Seller — {X} successful sales with {Y}% completion rate."

**Seller warning — post-listing:**
> "Heads up: If you don't transfer the ticket within 24 hours, the sale will be cancelled and the buyer automatically refunded. Repeated failures may result in account suspension."

**Buyer warning — before dispute:**
> "Before reporting an issue, please check: Did you check your email (including spam)? Did you check your {platform} app? Transfers can sometimes take up to 30 minutes."

**System message — auto-release approaching (sent to buyer at 48h):**
> "Reminder: You purchased tickets for {event}. If you've received them, please confirm in the app. If you don't respond within 24 hours, payment will be released to the seller automatically."

---

## IMPLEMENTATION PRIORITY (V1, 1-2 Day Sprint)

### Day 1: Backend + Data

| Priority | Task | Effort |
|----------|------|--------|
| P0 | Run migration `011_v1_transfer_enhancements.sql` | 15 min |
| P0 | Update `mark_transfer_sent` RPC signature | 15 min |
| P0 | Update `buyer_dispute_transfer` RPC signature | 15 min |
| P0 | Create `set_transfer_delivery_info` RPC | 15 min |
| P0 | Create `admin_resolve_dispute` RPC | 15 min |
| P1 | Add TypeScript types | 30 min |
| P1 | Create `platformInstructions.ts` | 1 hr |
| P1 | Update storage policies for new paths | 30 min |

### Day 2: Frontend

| Priority | Task | Effort |
|----------|------|--------|
| P0 | Add platform selection to listing creation flow | 1 hr |
| P0 | Add proof upload to listing creation flow | 1.5 hr |
| P0 | Build delivery info collection (post-checkout) | 1 hr |
| P0 | Revive + refactor `transfer/send/[id].tsx` | 2 hr |
| P0 | Revive + refactor `transfer/receive/[id].tsx` | 2 hr |
| P1 | Add `PlatformInstructions` component | 1 hr |
| P1 | Add dispute reason/evidence UI | 1 hr |
| P2 | Seller commitment checkbox | 30 min |

### Post-Launch (Week 1-2)

| Priority | Task |
|----------|------|
| P1 | Build admin dispute review dashboard |
| P1 | Implement `seller_flags` table + cron |
| P2 | Duplicate proof detection |
| P2 | Push notification copy updates |
| P2 | Auto-release reminder notification (48h) |

---

## COMPATIBILITY NOTES

- **No breaking changes:** All new columns have defaults or are nullable.
- **Existing transfers:** Continue working as-is. New fields are NULL on existing rows.
- **Existing listings:** Default `ticket_platform = 'other'`. Existing listings remain valid.
- **RPC backward compatibility:** New parameters on `mark_transfer_sent` and `buyer_dispute_transfer` all have `DEFAULT NULL`, so existing callsites work without changes.
- **Frontend rollout:** New screens can be behind feature flags. Existing ListingDetailScreen transfer buttons continue working.
