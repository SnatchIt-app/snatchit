# SMS Phone Verification — Implementation Audit

Date: 2026-07-08 · Supabase Phone Auth only. Email/password remains primary auth. Selling gated; browsing/bidding/buying untouched. No Stripe charge / payout-release changes.

## Files changed
| File | Change |
|------|--------|
| `app/settings/verify-phone.tsx` | **New** verification screen: phone entry → OTP send → 6-digit verify → verified status; resend w/ 30s cooldown, loading + graceful error states |
| `app/settings/index.tsx` | "Phone Verification" row (Account section) |
| `app/_layout.tsx` | Route registration |
| `src/screens/CreateListingScreen.tsx` | Gate 0 before payout gate: "Verify your phone number to sell tickets on Snatch It." + **Verify phone** button → `/settings/verify-phone` |
| `app/settings/privacy.tsx` | Phone bullet updated: verification-only use, never public, never marketing |
| `supabase/migrations/038_listing_requires_verified_phone.sql` | Server-side guard (applied ✓) |

## Supabase auth methods used
- `supabase.auth.updateUser({ phone: '+1XXXXXXXXXX' })` — attaches phone to the signed-in email account and triggers the OTP SMS (phone_change flow; does NOT replace email/password auth)
- `supabase.auth.verifyOtp({ phone, token, type: 'phone_change' })` — confirms; Supabase sets `auth.users.phone` + `phone_confirmed_at`
- `supabase.auth.getUser()` — fresh `phone_confirmed_at` check in the listing gate and screen

## DB guard (applied + verified live via pg_policy)
- `public.phone_verified()` — SECURITY DEFINER, reads `auth.users.phone_confirmed_at` for `auth.uid()`. Chosen over a mirrored profile flag because `phone_confirmed_at` is written only by Supabase Auth (clients can't forge it) and needs no sync trigger.
- Listings INSERT policy now: `seller_id = auth.uid() AND stripe_onboarding_complete AND phone_verified()`.
- `service_role` bypasses RLS → admin tooling and demo seeding unaffected.

## Dashboard settings REQUIRED (cannot be done from CLI — do before next build ships)
1. **Auth → Providers → Phone**: enable; provider = Twilio (Account SID, Auth Token, Verify Service SID or Messaging Service SID).
2. **Auth → Rate Limits**: set SMS sends/hour (cost control — start low, e.g. 30/hr).
3. **Auth → Providers → Phone**: OTP expiry (default 60s–10min; recommend 5 min) and max resend frequency.
4. Twilio side: Verify service (or A2P 10DLC-registered Messaging Service for US delivery).

## ⚠️ Sequencing risk (read before TestFlight)
The RLS guard is **live now**, but the current TestFlight build has no verify-phone screen and the Phone provider isn't enabled yet. Until (a) Twilio is configured in the dashboard AND (b) the next build ships, **no user can create a new listing through the UI** (demo/admin seeding via service role still works). If you need to unblock listing creation temporarily:
```sql
-- rollback to 036 behavior (payout-only guard):
DROP POLICY IF EXISTS "listings: auth insert" ON public.listings;
CREATE POLICY "listings: auth insert" ON public.listings FOR INSERT
  WITH CHECK (seller_id = auth.uid() AND EXISTS (SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid() AND p.stripe_onboarding_complete = true));
```

## Privacy / App Review
- Phone never selected in any public query (`public_profiles` view and profile screens expose no phone); verification screen states the number is never shown publicly or used for marketing; privacy policy updated to match.

## Exact commands (executed)
```bash
npx tsc --noEmit                 # clean
supabase db push                 # 038 applied
git add … && git commit && git push
```

## EAS build required?
**Yes** — new screen + gate are client code. Enable Twilio in the dashboard **before** distributing that build.
