# Phase A — V1 Transfer Enhancements Implementation Plan

**Generated:** 2026-04-02 | **Scope:** Minimum viable trust enhancements to the existing transfer system | **Status:** Ready for implementation

---

## SECTION 1 — Exact Migration SQL

Create file: `supabase/migrations/011_v1_transfer_enhancements.sql`

```sql
-- =============================================================================
-- Migration 011: V1 Transfer Enhancements (Phase A)
-- =============================================================================
-- Adds: ticket_platform, proof_of_ownership, seller_commitment on listings
--       delivery_email, delivery_phone, transfer_evidence, dispute details on transfers
--       Three new/updated RPCs: set_transfer_delivery_info, mark_transfer_sent (extended),
--       buyer_dispute_transfer (extended), admin_resolve_dispute (new)
--
-- PRESERVES: All existing payout/refund/dispute/auto-release architecture.
-- Safe to run: all DDL uses IF NOT EXISTS / OR REPLACE.
-- =============================================================================


-- ─────────────────────────────────────────────────────────────────────────────
-- 1. LISTINGS: platform selection + proof of ownership + seller commitment
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.listings
  ADD COLUMN IF NOT EXISTS ticket_platform TEXT NOT NULL DEFAULT 'other',
  ADD COLUMN IF NOT EXISTS proof_of_ownership_path TEXT,
  ADD COLUMN IF NOT EXISTS seller_commitment_accepted_at TIMESTAMPTZ;

-- Add CHECK constraint separately (safe if column already exists)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'listings_ticket_platform_check'
      AND conrelid = 'public.listings'::regclass
  ) THEN
    ALTER TABLE public.listings
      ADD CONSTRAINT listings_ticket_platform_check
      CHECK (ticket_platform IN ('dice', 'eventbrite', 'posh', 'axs', 'ticketmaster', 'other'));
  END IF;
END $$;


-- ─────────────────────────────────────────────────────────────────────────────
-- 2. TRANSFERS: delivery info + transfer evidence + dispute details + resolution
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.transfers
  ADD COLUMN IF NOT EXISTS delivery_email TEXT,
  ADD COLUMN IF NOT EXISTS delivery_phone TEXT,
  ADD COLUMN IF NOT EXISTS transfer_evidence_path TEXT,
  ADD COLUMN IF NOT EXISTS dispute_reason TEXT,
  ADD COLUMN IF NOT EXISTS dispute_evidence_path TEXT,
  ADD COLUMN IF NOT EXISTS dispute_notes TEXT,
  ADD COLUMN IF NOT EXISTS dispute_resolution TEXT,
  ADD COLUMN IF NOT EXISTS dispute_resolved_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS dispute_resolved_by UUID REFERENCES auth.users(id);

-- Add CHECK constraints separately
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'transfers_dispute_reason_check'
      AND conrelid = 'public.transfers'::regclass
  ) THEN
    ALTER TABLE public.transfers
      ADD CONSTRAINT transfers_dispute_reason_check
      CHECK (dispute_reason IN ('never_received', 'wrong_tickets', 'invalid_tickets', 'partial_delivery'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'transfers_dispute_resolution_check'
      AND conrelid = 'public.transfers'::regclass
  ) THEN
    ALTER TABLE public.transfers
      ADD CONSTRAINT transfers_dispute_resolution_check
      CHECK (dispute_resolution IN ('resolved_seller_paid', 'resolved_buyer_refunded', 'resolved_partial_refund'));
  END IF;
END $$;


-- ─────────────────────────────────────────────────────────────────────────────
-- 3. NEW RPC: set_transfer_delivery_info
-- Called by buyer post-purchase to provide email/phone for ticket delivery
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.set_transfer_delivery_info(
  p_transfer_id    UUID,
  p_delivery_email TEXT DEFAULT NULL,
  p_delivery_phone TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid;
  v_status    text;
  v_buyer_id  uuid;
BEGIN
  v_caller_id := coalesce(auth.uid(), NULL);

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unable to identify caller. Ensure the request is authenticated.';
  END IF;

  SELECT status, buyer_id
    INTO v_status, v_buyer_id
    FROM public.transfers
   WHERE id = p_transfer_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transfer not found.';
  END IF;

  IF v_buyer_id IS DISTINCT FROM v_caller_id THEN
    RAISE EXCEPTION 'Only the buyer can set delivery info.';
  END IF;

  -- Allow setting delivery info while pending or seller_sent (buyer might update late)
  IF v_status NOT IN ('pending', 'seller_sent') THEN
    RAISE EXCEPTION 'Cannot update delivery info in current status: %.', v_status;
  END IF;

  UPDATE public.transfers
     SET delivery_email = COALESCE(p_delivery_email, delivery_email),
         delivery_phone = COALESCE(p_delivery_phone, delivery_phone)
   WHERE id = p_transfer_id;
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- 4. UPDATED RPC: mark_transfer_sent (extended with evidence path)
-- Preserves existing signature (p_transfer_id, p_user_id), adds optional p_transfer_evidence_path
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.mark_transfer_sent(
  p_transfer_id            UUID,
  p_user_id                UUID,
  p_transfer_evidence_path TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid;
  v_status    text;
  v_seller_id uuid;
BEGIN
  v_caller_id := coalesce(auth.uid(), p_user_id);

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unable to identify caller. Ensure the request is authenticated.';
  END IF;

  SELECT status, seller_id
    INTO v_status, v_seller_id
    FROM public.transfers
   WHERE id = p_transfer_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transfer not found.';
  END IF;

  IF v_seller_id IS DISTINCT FROM v_caller_id THEN
    RAISE EXCEPTION 'Only the seller can mark a transfer as sent.';
  END IF;

  IF v_status <> 'pending' THEN
    RAISE EXCEPTION 'Transfer cannot be marked as sent from current status: %.', v_status;
  END IF;

  UPDATE public.transfers
     SET status                 = 'seller_sent',
         seller_sent_at         = now(),
         auto_release_at        = now() + interval '72 hours',
         transfer_evidence_path = COALESCE(p_transfer_evidence_path, transfer_evidence_path)
   WHERE id = p_transfer_id;
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- 5. UPDATED RPC: buyer_dispute_transfer (extended with reason/evidence/notes)
-- Preserves existing signature (p_transfer_id, p_user_id), adds optional dispute fields
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.buyer_dispute_transfer(
  p_transfer_id          UUID,
  p_user_id              UUID DEFAULT NULL,
  p_dispute_reason       TEXT DEFAULT NULL,
  p_dispute_evidence_path TEXT DEFAULT NULL,
  p_dispute_notes        TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid;
  v_status    text;
  v_buyer_id  uuid;
BEGIN
  v_caller_id := coalesce(auth.uid(), p_user_id);

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unable to identify caller. Ensure the request is authenticated.';
  END IF;

  SELECT status, buyer_id
    INTO v_status, v_buyer_id
    FROM public.transfers
   WHERE id = p_transfer_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transfer not found.';
  END IF;

  IF v_buyer_id IS DISTINCT FROM v_caller_id THEN
    RAISE EXCEPTION 'Only the buyer can dispute a transfer.';
  END IF;

  -- Idempotent: if already disputed, just return
  IF v_status = 'disputed' THEN
    RETURN;
  END IF;

  IF v_status <> 'seller_sent' THEN
    RAISE EXCEPTION 'Cannot dispute transfer in current status: %.', v_status;
  END IF;

  UPDATE public.transfers
     SET status                = 'disputed',
         disputed_at           = now(),
         dispute_reason        = COALESCE(p_dispute_reason, dispute_reason),
         dispute_evidence_path = COALESCE(p_dispute_evidence_path, dispute_evidence_path),
         dispute_notes         = COALESCE(p_dispute_notes, dispute_notes)
   WHERE id = p_transfer_id;
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- 6. NEW RPC: admin_resolve_dispute
-- For admin SQL-level use only in V1 (no admin UI yet)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.admin_resolve_dispute(
  p_transfer_id UUID,
  p_resolution  TEXT,
  p_admin_id    UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_resolution NOT IN ('resolved_seller_paid', 'resolved_buyer_refunded', 'resolved_partial_refund') THEN
    RAISE EXCEPTION 'Invalid resolution type: %', p_resolution;
  END IF;

  UPDATE public.transfers
     SET dispute_resolution  = p_resolution,
         dispute_resolved_at = now(),
         dispute_resolved_by = p_admin_id
   WHERE id = p_transfer_id
     AND status = 'disputed';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transfer not found or not in disputed state.';
  END IF;
END;
$$;
```

---

## SECTION 2 — Exact Files to Modify

### New files to create:

| # | File | Purpose |
|---|------|---------|
| 1 | `supabase/migrations/011_v1_transfer_enhancements.sql` | Migration (Section 1 above) |
| 2 | `src/lib/platformInstructions.ts` | Platform instruction engine — static JSON map of platform → seller/buyer step-by-step guides |
| 3 | `src/components/PlatformInstructions.tsx` | Reusable component rendering platform-specific steps for seller or buyer role |
| 4 | `src/components/ImageUploadField.tsx` | Reusable image upload component for proof/evidence (wraps existing `useImageUpload` hook pattern) |
| 5 | `src/components/DeliveryInfoForm.tsx` | Small form component for buyer to enter delivery_email / delivery_phone |
| 6 | `src/components/DisputeForm.tsx` | Dispute reason picker + evidence upload + notes field |

### Existing files to modify:

| # | File | What changes |
|---|------|-------------|
| 7 | `src/types/index.ts` | Add `TicketPlatform`, `DisputeReason`, `DisputeResolution` types; add Phase A fields to `Listing` type; create `Transfer` interface |
| 8 | `src/screens/CreateListingScreen.tsx` | Add platform picker step, proof-of-ownership upload, seller commitment checkbox. Update insert call to include `ticket_platform`, `proof_of_ownership_path`, `seller_commitment_accepted_at` |
| 9 | `app/transfer/send/[id].tsx` | Full rewrite: show buyer delivery info, platform-specific sending instructions, transfer evidence upload, call updated `mark_transfer_sent` with evidence path |
| 10 | `app/transfer/receive/[id].tsx` | Full rewrite: delivery info form (if not yet provided), platform-specific receiving instructions, confirm/dispute with new dispute form, call updated `buyer_dispute_transfer` with reason/evidence/notes |
| 11 | `src/screens/ListingDetailScreen.tsx` | After payment success, navigate to `/transfer/receive/[id]` instead of staying on listing. Update `handleMarkSent` to navigate to `/transfer/send/[id]`. Remove inline transfer action buttons (move to dedicated screens). Fetch `ticket_platform` from listing join. |
| 12 | `app/checkout/[id].tsx` | After successful payment + `ensure_transfer_exists`, navigate to `app/transfer/receive/[id]` for delivery info collection |
| 13 | `app/_layout.tsx` | Already has `transfer/receive/[id]` and `transfer/send/[id]` as Stack.Screen entries — **no changes needed** |

---

## SECTION 3 — Smallest Implementation Order

Each step is independently deployable and testable.

### Step 1: Migration + Types (backend-only, zero UI risk)
- Create `supabase/migrations/011_v1_transfer_enhancements.sql`
- Run migration against Supabase
- Update `src/types/index.ts` with new types and fields
- **Test:** Verify columns exist via SQL Editor; verify RPCs callable with new params

### Step 2: Platform Instruction Engine (new files, no existing code touched)
- Create `src/lib/platformInstructions.ts` (full platform map from V2 design doc Section 3.2)
- Create `src/components/PlatformInstructions.tsx` (render component)
- **Test:** Import component in a test screen, verify renders for each platform

### Step 3: Reusable upload + form components (new files, no existing code touched)
- Create `src/components/ImageUploadField.tsx`
- Create `src/components/DeliveryInfoForm.tsx`
- Create `src/components/DisputeForm.tsx`
- **Test:** Import in isolation, verify rendering

### Step 4: Create Listing Screen enhancements
- Modify `src/screens/CreateListingScreen.tsx`:
  - Add `ticketPlatform` state (default `'other'`)
  - Add platform picker section (after transfer method)
  - Add proof-of-ownership upload section (using ImageUploadField, uses existing `useImageUpload` pattern with bucket path `{listing_id}/proof/`)
  - Add seller commitment checkbox before publish button
  - Update `supabase.from('listings').insert({...})` to include the 3 new fields
  - Block publish if proof not uploaded or commitment not checked
- **Test:** Create a listing with all new fields, verify in SQL Editor

### Step 5: Seller Send Screen rewrite
- Rewrite `app/transfer/send/[id].tsx`:
  - Fetch transfer with joined listing (to get `ticket_platform`) and buyer delivery info
  - Show `PlatformInstructions` component (role: 'seller')
  - Show buyer delivery info (email/phone)
  - Add `ImageUploadField` for transfer evidence upload
  - On "Mark as Sent": upload evidence → call `mark_transfer_sent` with evidence path
  - Post-send: show waiting state with auto-release countdown
- **Test:** Navigate to send screen, upload evidence, mark as sent, verify DB

### Step 6: Buyer Receive Screen rewrite
- Rewrite `app/transfer/receive/[id].tsx`:
  - Fetch transfer with joined listing (to get `ticket_platform`)
  - If `delivery_email` and `delivery_phone` are null: show `DeliveryInfoForm`, call `set_transfer_delivery_info` on submit
  - Show `PlatformInstructions` component (role: 'buyer')
  - Show "I Got My Tickets" → calls existing `confirm-and-release` edge function
  - Show "I Haven't Received Them" → opens `DisputeForm` → calls updated `buyer_dispute_transfer`
  - Post-dispute: show "Issue reported, payment protected" message
- **Test:** Navigate to receive screen, enter delivery info, confirm or dispute

### Step 7: Navigation wiring
- Modify `src/screens/ListingDetailScreen.tsx`:
  - Seller: "Mark as Sent" button now navigates to `/transfer/send/${transferId}` instead of calling RPC inline
  - Buyer: "Confirm Received" / "Report Issue" buttons navigate to `/transfer/receive/${transferId}`
  - Remove inline transfer action handlers (or keep as fallback behind a flag)
- Modify `app/checkout/[id].tsx`:
  - After payment success + `ensure_transfer_exists`, add navigation to `/transfer/receive/${transferId}`
- **Test:** Full end-to-end flow: list → buy → delivery info → seller send → buyer confirm

---

## SECTION 4 — Exact Implementation Prompt for Claude Code

Copy the prompt below into Claude Code to execute each step.

---

### PROMPT:

```
You are implementing Phase A of SnatchIt's V1 transfer enhancements. Follow the implementation plan in PHASE_A_IMPLEMENTATION_PLAN.md in the project root.

CRITICAL CONSTRAINTS:
- Do NOT create any new tables
- Do NOT modify existing edge functions (confirm-and-release, stripe-webhook, etc.)
- Do NOT change any payout/refund/auto-release logic
- Do NOT add seller flags, OCR, email parsing, scoring, or badges
- Preserve all existing RPC signatures as backward-compatible (new params are all DEFAULT NULL)
- Use the existing `useImageUpload` hook pattern from src/hooks/useImageUpload.ts for all image uploads
- Use the existing theme system from src/theme for all styling
- Use the existing supabase client from src/lib/supabase

IMPLEMENTATION ORDER (do each step fully before moving to the next):

STEP 1 — MIGRATION + TYPES
1. Create supabase/migrations/011_v1_transfer_enhancements.sql with the exact SQL from PHASE_A_IMPLEMENTATION_PLAN.md Section 1
2. Update src/types/index.ts:
   - Add: export type TicketPlatform = 'dice' | 'eventbrite' | 'posh' | 'axs' | 'ticketmaster' | 'other';
   - Add: export type DisputeReason = 'never_received' | 'wrong_tickets' | 'invalid_tickets' | 'partial_delivery';
   - Add: export type DisputeResolution = 'resolved_seller_paid' | 'resolved_buyer_refunded' | 'resolved_partial_refund';
   - Add ticket_platform, proof_of_ownership_path, seller_commitment_accepted_at to the Listing type
   - Add a full Transfer interface with all existing + new columns (id, listing_id, payment_id, seller_id, buyer_id, transfer_method, status, created_at, seller_sent_at, buyer_confirmed_at, expires_at, expired_at, disputed_at, auto_release_at, payout_released_at, stripe_transfer_id, delivery_email, delivery_phone, transfer_evidence_path, dispute_reason, dispute_evidence_path, dispute_notes, dispute_resolution, dispute_resolved_at, dispute_resolved_by)

STEP 2 — PLATFORM INSTRUCTION ENGINE
1. Create src/lib/platformInstructions.ts with the full PLATFORM_INSTRUCTIONS map from V2_TRANSFER_SYSTEM_DESIGN.md Section 3.2 (dice, eventbrite, posh, axs, ticketmaster, other)
2. Create src/components/PlatformInstructions.tsx:
   - Props: platform: TicketPlatform, role: 'seller' | 'buyer', buyerEmail?: string, buyerPhone?: string
   - Looks up instructions from the map
   - Renders numbered steps, substituting {buyer_email} and {buyer_phone} placeholders
   - Shows warnings in a yellow callout
   - Shows tips in a collapsible section
   - Uses existing theme (colors, fontSize, radius, spacing from src/theme)

STEP 3 — REUSABLE COMPONENTS
1. Create src/components/ImageUploadField.tsx:
   - Props: label: string, bucketPath: string, onUpload: (path: string) => void, existingPath?: string
   - Uses useImageUpload hook pattern from src/hooks/useImageUpload.ts
   - Shows upload button, preview of selected image, upload progress
   - On completion calls onUpload with the storage path
2. Create src/components/DeliveryInfoForm.tsx:
   - Props: transferMethod: 'email' | 'mobile_transfer', onSubmit: (email: string | null, phone: string | null) => void, loading?: boolean
   - Shows email field if transfer method is 'email', phone field if 'mobile_transfer', both if needed
   - Submit button calls onSubmit
3. Create src/components/DisputeForm.tsx:
   - Props: onSubmit: (reason: DisputeReason, evidencePath: string | null, notes: string) => void, loading?: boolean
   - Reason picker (4 options from DisputeReason type)
   - Optional evidence upload (uses ImageUploadField)
   - Notes text area
   - Submit button

STEP 4 — CREATE LISTING SCREEN
Modify src/screens/CreateListingScreen.tsx:
1. Add state: ticketPlatform (default 'other'), proofPath (string | null), commitmentAccepted (boolean)
2. After the Transfer Method section, add a "Ticket Platform" section with a picker for the 6 platforms (dice, eventbrite, posh, axs, ticketmaster, other) styled identically to the existing pill selectors
3. After the cover image upload, add a "Proof of Ownership" section using ImageUploadField with bucket path that will be `{listing.id}/proof/filename` — since we don't have the listing ID yet, upload to a temp path and note it
   - IMPORTANT: Since listing ID isn't known until insert, use a two-step approach:
     a. Upload proof image to a temp path first (e.g., `temp/{userId}/{timestamp}/proof.jpg`)
     b. After listing insert, we have the ID — store the temp path in proof_of_ownership_path (we can move it later or just use the temp path)
     c. OR simpler: upload proof image AFTER listing insert (like cover image pattern), then update the listing row
   - Actually, follow the exact same pattern as coverUpload: upload first, get path, include in insert
4. Before the Publish button, add a commitment checkbox: "I confirm I own these tickets and will transfer them within 24 hours of sale"
5. Validation: block publish if proof not uploaded OR commitment not checked
6. Update the .insert() call to include: ticket_platform, proof_of_ownership_path, seller_commitment_accepted_at (set to new Date().toISOString() when checkbox is checked)

STEP 5 — SELLER SEND SCREEN
Rewrite app/transfer/send/[id].tsx:
1. Fetch transfer with: id, listing_id, status, transfer_method, expires_at, auto_release_at, delivery_email, delivery_phone, transfer_evidence_path, buyer:profiles!buyer_id(display_name), listing:listings!listing_id(event_name, ticket_platform)
2. Show PlatformInstructions component with platform from listing, role='seller', passing buyer's delivery_email and delivery_phone
3. Show buyer delivery info card (email and/or phone)
4. If status is 'pending': show ImageUploadField for transfer evidence, then "Mark as Sent" button
5. On Mark as Sent: upload evidence to `{listing_id}/transfer-evidence/{timestamp}.jpg`, then call supabase.rpc('mark_transfer_sent', { p_transfer_id: id, p_user_id: userId, p_transfer_evidence_path: evidencePath })
6. If status is 'seller_sent': show "Waiting for buyer" with auto_release_at countdown
7. Keep existing back button and countdown timer pattern from current code

STEP 6 — BUYER RECEIVE SCREEN
Rewrite app/transfer/receive/[id].tsx:
1. Fetch transfer with: id, status, transfer_method, expires_at, delivery_email, delivery_phone, seller:profiles!seller_id(display_name), listing:listings!listing_id(event_name, ticket_platform)
2. If delivery_email AND delivery_phone are both null AND status is 'pending': show DeliveryInfoForm, on submit call supabase.rpc('set_transfer_delivery_info', { p_transfer_id: id, p_delivery_email: email, p_delivery_phone: phone })
3. Show PlatformInstructions with platform from listing, role='buyer'
4. If status is 'pending': show "Waiting for seller to send"
5. If status is 'seller_sent': show two buttons:
   - "I Got My Tickets" → calls supabase.functions.invoke('confirm-and-release', { body: { transfer_id: id } }) (same as existing handleConfirmReceived in ListingDetailScreen)
   - "I Haven't Received Them" → shows DisputeForm → on submit call supabase.rpc('buyer_dispute_transfer', { p_transfer_id: id, p_user_id: userId, p_dispute_reason: reason, p_dispute_evidence_path: evidencePath, p_dispute_notes: notes })
6. If status is 'buyer_confirmed': show success message
7. If status is 'disputed': show "Issue reported — our team will review within 24 hours. Your payment is protected."

STEP 7 — NAVIGATION WIRING
1. In src/screens/ListingDetailScreen.tsx:
   - Change handleMarkSent to navigate: router.push(`/transfer/send/${transferId}`)
   - Change handleConfirmReceived to navigate: router.push(`/transfer/receive/${transferId}`)
   - Change handleReportIssue to navigate: router.push(`/transfer/receive/${transferId}`)
   - Keep the transfer status display on the listing screen (it still shows status, just actions are on the dedicated screens)
2. In app/checkout/[id].tsx:
   - After ensure_transfer_exists returns a transfer ID, navigate to /transfer/receive/{transferId}

After each step, verify the changes compile by running: npx expo export --platform ios 2>&1 | tail -20
```

---

STEP COMPLETE — WAITING FOR NEXT RUN
