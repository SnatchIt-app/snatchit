# Stripe Connect Onboarding Friction Fixes — Audit

Date: 2026-07-07 · Scope: onboarding friction only. No SMS, no charge logic, no payout-release changes, no webhook changes.

## Files changed
| File | Change |
|------|--------|
| `supabase/functions/create-connect-account/index.ts` | New-account branch only: individual Express account params + user email |
| `app/settings/payout-setup.tsx` | Individual-friendly copy (not_connected + onboarding_required states) |
| `src/screens/CreateListingScreen.tsx` | Payout-gate alert copy (web + native) |
| `supabase/migrations/036_listing_requires_payout_setup.sql` | Server-side INSERT guard on listings |
| `supabase/migrations/037_drop_legacy_listing_insert_policies.sql` | Drops 2 legacy permissive INSERT policies that bypassed 036 |

## Exact Stripe account params now sent (NEW accounts only)
```
type=express
country=US
email=<user's auth email, omitted if unavailable>
business_type=individual
capabilities[transfers][requested]=true
business_profile[product_description]=Individual reselling event tickets on Snatch It
metadata[user_id]=<user id>
```

## Existing accounts affected?
**No.** The new params live inside the `if (!accountId)` branch, which only runs when the profile has no `stripe_connect_id`. Existing accounts are never mutated; status checks and account-link generation are unchanged.

## Copy (Task 2)
- Payout setup screen: "Verify your identity and add a bank account to get paid. This usually takes about 2 minutes. Anyone can sell — no business registration needed." + "Selling as an individual is the default."
- Create-listing gate (web confirm + native alert): "Verify your identity and add a bank account to get paid. This usually takes about 2 minutes."

## Server-side guard status (Task 3)
- **Before:** publish was client-gated only. RLS allowed any `seller_id = auth.uid()` insert. Audit also found two undocumented legacy INSERT policies in production (`listings_insert_authenticated`, `listings_insert_own`) — permissive policies OR together, so any single weak policy defeats the gate.
- **After (verified live via pg_policy):** exactly ONE INSERT policy remains —
  `seller_id = auth.uid() AND EXISTS (profiles.stripe_onboarding_complete = true)`.
- Safe paths: `service_role` bypasses RLS (admin tooling, demo seeding, edge functions). Flag-lag safe: `stripe_onboarding_complete` is written by create-connect-account's status check and the `account.updated` webhook before the client gate ever passes.

## Deploy commands (all executed)
```bash
supabase db push                                   # 036 + 037 applied ✓
supabase functions deploy create-connect-account   # deployed ✓
```

## EAS build required?
**Yes, eventually** — the copy changes (payout-setup screen, create-listing alert) ship in the next JS bundle/binary. Backend changes (Stripe params, RLS guard) are live now and work with the current TestFlight build. No build was run per instructions.
