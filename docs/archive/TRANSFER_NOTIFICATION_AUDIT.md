# Transfer Notification & Buyer-Visible Proof — Implementation Audit

Date: 2026-06-22 · Scope: transaction-progress notifications + buyer-visible seller proof. Payment/Stripe charge logic untouched. No EAS build.

## Files changed
| File | Change |
|------|--------|
| `supabase/migrations/034_transfer_notifications.sql` | **New.** Idempotency table, notify-transfer trigger, proof-docs buyer/seller read policy. |
| `supabase/functions/notify-transfer/index.ts` | **New** edge fn. Immediate seller/buyer push on `transfer_created` + `tickets_marked_sent`. |
| `supabase/functions/enforce-transfer-expiry/index.ts` | Added **Phase 3** reminder sweep (seller + buyer), isolated in its own try/catch. Phases 1–2 unchanged. |
| `src/providers/NativeAppShell.native.tsx` | Deep-link routing for `seller_action` / `buyer_confirm` / `buyer_info_needed` → transfer screens. |
| `app/transfer/send/[id].tsx` | Seller proof now uploads to **private** `proof-docs` bucket (was public `auction-media`). |
| `app/transfer/receive/[id].tsx` | Buyer fetches `transfer_evidence_path`, views seller proof via signed URL in `seller_sent` state. |

## DB changes (migration 034)
- **`public.transfer_notifications`** — PK `(transfer_id, event_type)` = the dedupe key. RLS on, `REVOKE ALL` from anon/authenticated (service-role only). `ON DELETE CASCADE` with transfers.
- **`notify_transfer_event()`** trigger fn (SECURITY DEFINER, Vault `service_role_key` + `net.http_post`, exception-swallowed) on:
  - `AFTER INSERT ON transfers` → `transfer_created`
  - `AFTER UPDATE OF status … WHEN NEW.status='seller_sent'` → `tickets_marked_sent`
- **Storage policy** `"proof-docs transfer party read"` (SELECT) — a transfer's buyer **or** seller may read the exact object named by `transfer_evidence_path`. Nothing else.
- No new indexes: reminder sweeps reuse existing partial indexes `idx_transfers_pending_expires` and `idx_transfers_seller_sent_auto_release`.

## Push events added
| Event (data.type) | Trigger | Recipient | Copy | Deep link |
|---|---|---|---|---|
| `seller_action` | `transfer_created` (insert) | seller | "Action needed: send the tickets" | `/transfer/send/{id}` |
| `buyer_info_needed` | `transfer_created` (no delivery info) | buyer | "Add your transfer info…" | `/transfer/receive/{id}` |
| `buyer_confirm` | `tickets_marked_sent` (→seller_sent) | buyer | "Tickets sent — confirm once received" | `/transfer/receive/{id}` |
| `seller_action` (reminder) | cron, ≤6h before `expires_at` | seller | "Reminder: send the tickets to complete your sale" | `/transfer/send/{id}` |
| `buyer_confirm` (reminder) | cron, ≤24h before `auto_release_at` | buyer | "Reminder: confirm your tickets…" | `/transfer/receive/{id}` |

Idempotency event_types logged: `seller_action_required`, `buyer_transfer_info_needed`, `buyer_confirmation_needed`, `transfer_reminder_seller`, `transfer_reminder_buyer`.

## Proof access rules
- Seller proof stored in **private** `proof-docs` at `<seller_uid>/transfer-evidence/<ts>.<ext>` (033 owner-insert policy covers seller).
- Buyer reads it only via a **signed URL** (`createSignedUrl`, 1h); the new SELECT policy authorizes buyer + seller of that transfer. Admin/service-role bypass RLS.
- Bucket stays `public=false`. Proof is never in any public listing/profile query. No public URL is ever generated for it.

## Reminders timing
- **Seller:** fires once when `now() < expires_at < now()+6h` (≈18h into the 24h send window). One row per transfer (`transfer_reminder_seller`).
- **Buyer:** fires once when `now() < auto_release_at < now()+24h` (≈48h into the 72h confirm window). One row (`transfer_reminder_buyer`).
- Cron cadence: existing every-2-min `enforce-transfer-expiry`. No new schedule, no new sweep window → cannot extend a transfer's lifetime or break expiry/auto-release.

## Edge cases
- **Idempotent / no spam:** every send is gated on a successful insert into `transfer_notifications` (`ON CONFLICT DO NOTHING` + `.select()`); on DB error we **skip** the send, never duplicate. Trigger retries are deduped.
- **No infinite loops:** triggers are fire-and-forget (pg_net, exception-swallowed); edge fns always return 200 so pg_net never retry-storms.
- **Action never blocked:** a notification failure can never block the transfer insert / mark-sent (exception handler in trigger).
- **Overlap (minor):** `stripe-webhook` still sends its existing "Your ticket sold!" push on purchase. The buyer now gets a separate "Action needed" push too — complementary, not duplicate. *P2: optionally dedupe by routing the existing `ticket_sold` push to the send screen and dropping one.*
- **Legacy transfers:** proof uploaded before 034 lives in `auction-media` (public); buyer signed-URL view applies to new `proof-docs` uploads only. No backfill (P2).
- **Window mismatch:** if a transfer is created with <6h to expiry (not the case today — webhook sets 24h), the seller reminder may not fire; the immediate `seller_action` push still does.

## NOT implemented (P2 — out of scope / unsafe to bundle)
- Dispute-evidence upload UI + reason/notes capture (RPC params exist, no UI).
- Email channel for transfer notifications (push-only; email remains moderation-only, gated `EMAIL_ENABLED`).
- Backfill of legacy `auction-media` proofs into `proof-docs`.
- `ticket_sold` push dedupe/routing.

## Exact commands (run by operator — not auto-applied)
```bash
# 1. Apply DB migration (production)
supabase db push                      # or: supabase migration up

# 2. Deploy edge functions
supabase functions deploy notify-transfer
supabase functions deploy enforce-transfer-expiry

# 3. Verify migration landed
supabase migration list               # expect 034 present

# 4. Commit
git add .
git commit -m "feat(transfers): progress notifications + buyer-visible seller proof"
git push
```
No new secrets required (reuses `SUPABASE_SERVICE_ROLE_KEY` / `INTERNAL_CRON_SECRET` / Vault `service_role_key`). **No EAS build required for the backend**; the client deep-link + proof-viewer changes ship in the next app build (not triggered here).
