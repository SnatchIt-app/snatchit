# RC integration — Tickets ownership RPC + filter sheet action bar

Branch `publish/ui-v2-integration`. No production deployment and no database
mutation occurred; every production query in this work was read-only.

## Migration version

**`20260909000000_kernel_my_tickets_read`**

Chosen because it is greater than every migration currently applied
(max applied lexical version `20260902003623`; max applied 1xx-sequence version
`120`) and greater than every unapplied migration already in this branch
(`20260906100000`–`20260906130000`). **110 is occupied in production by
`signing_key_insert_guard` and was not reused.** The original Core draft carried
this RPC at 110; it was renumbered, and its header, rollback pointer and pgTAP
references were rewritten to the new version.

## Rebase onto the 110–120 production schema

The RPC's dependencies were verified against the live post-120 schema by
read-only query, not assumed:

- all 20 referenced columns exist —
  `kernel.tickets`(current_owner_id, event_session_id, ticket_type_id, state,
  resale_state), `catalog.event_session`(session_id, event_id, session_label,
  starts_at, ends_at, doors_at), `catalog.event`(event_id, title, venue_id,
  hero_image_ref), `catalog.venue`(venue_id, name),
  `venue.ticket_type`(ticket_type_id, name, kind)
- both projected vocabularies still match their live CHECK constraints exactly:
  `state` ∈ (issued, active, scanned, voided, expired);
  `resale_state` ∈ (none, listed, locked, refund_hold, dispute_hold)
- `public.get_my_tickets` does not exist in production — no collision

110–120 are signing-key, door-manifest and ops-console packages; none of them
touches an object this read depends on.

## GATE-2

One new `public` function, nothing else. Baseline bumped 86 → 87 in both places
that pin it: `.github/workflows/ci.yml` (EXPECT_FUNCS) and
`supabase/tests/162_payout_reversal_and_obligation_recovery.sql` (P2). Tables 30,
policies 37, triggers 32 are unchanged. Fresh local replay reports
`tables=30 functions=87 policies=37 triggers=32`, matching both.

## Verification

Fresh no-Docker replay: **129/129 migrations applied**, no file skipped.

pgTAP `176_my_tickets_read.sql` — **20/20**:

| Requirement | Assertions |
|---|---|
| authenticated owner receives only their own groups | B1 (exactly 3 own groups), B8 (another user's event never appears) |
| unauthenticated fails closed | A5 (anon has no EXECUTE), D1 (anon denied, never served empty), D2 (null uid raises `tickets_unauthenticated`) |
| empty native issuance returns a valid empty state | C1 (authenticated, no tickets → empty set, not an error) |
| cross-user reads impossible | A1 (no arguments — binds to `auth.uid()`), B8 |
| QR / barcode / Apple Wallet not implied | A6 (no owner id, serial, signing, payment or credential column on the projection), A7 (only the event-first fields) |

Full pgTAP suite: **4067/4067, ALL-PASS**, no regressions and no local-only
deltas.

## Filter sheet

Ported from `93d6a14`. Root cause was React Native's `flexShrink: 0` default:
`Sheet`'s footer is a row and both actions were `<Button block>` (`width: 100%`),
so the row demanded twice the content width plus the gap and Apply was pushed off
the right edge. `SheetAction` (`flex: 1, flexBasis: 0, minWidth: 0`) makes each
action an equal share. Width matrix asserted arithmetically — 320, 375, 393, 430
and 852 all fit exactly, every share ≥ 44pt.

## API dependency for the release-integration session

`public.get_my_tickets()` ships in this branch as a migration but is **not
applied**. Until it is, the Tickets tab calls an RPC that does not exist in
production and will surface a transport error rather than the empty state. The
release-integration session must apply `20260909000000` as part of the shared RC.

Native issuance remains dark (`feature.native_issuance_enabled = false`), so once
applied the correct result is a valid **empty** Tickets state for every caller
until the backend is active. Empty must not be treated as an error.
