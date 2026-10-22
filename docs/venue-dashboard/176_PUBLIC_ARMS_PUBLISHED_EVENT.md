# 176: public ticket arms require a published event (pgTAP 246)

> **Registry 176 / pgTAP 246, allocated by A** (`origin/a/registry-20261021`: `912c81aa` allocates it,
> and the tip `14f3e8ec` records "176 is written by F, reviewed by A"). **A reviews before this leaves
> draft.** It is applied nowhere: not on production, not on the sandbox, not on any hosted project.
> Nothing in this branch applies it, exposes `venue_api` or writes data.
>
> **Not yet run.** The heavy slot was held by another session when this was written, so the replay,
> pgTAP 246, the mutants and the rollback cycle have not been run. §7 lists the runs that are owed,
> each with the result this doc predicts.

Branch `venue/176-public-arms-published-event`, based on `origin/venue/api-read-views-provisional`
@ `8ccb26e1` (the fix/154 chain plus 159).

| File | What |
|---|---|
| `supabase/migrations/20261022000000_venue_public_arms_require_published_event.sql` | the two policy replacements, plus a post-condition `DO` block |
| `supabase/rollbacks/20261022000000_venue_public_arms_require_published_event_rollback.sql` | 081's two public arms, verbatim (diffed byte for byte against 081 lines 989–992 and 1019–1024) |
| `supabase/tests/246_venue_public_arms_require_published_event.sql` | 50 assertions, written in 226's style |
| `docs/venue-dashboard/176_READERS.md` | every reader of the two tables, on every ref, and what 176 does to each |

## 1. What and why (owner decision V-13)

A's review of 159 found the gap. 081's public arms never look at the parent event:

```sql
venue_ticket_type_sel_public      FOR SELECT TO authenticated USING (visibility = 'public')
venue_inventory_batch_sel_public  FOR SELECT TO authenticated
  USING (exists (select 1 from venue.ticket_type tt
                  where tt.ticket_type_id = venue.inventory_batch.ticket_type_id
                    and tt.visibility = 'public'))
```

So any signed-in user, with no org or venue role, reads a public ticket type's name and price, and its
batch's `remaining`, while the event is still a **draft**. That same user cannot read the draft in
`catalog.event`. The `venue_api` views do not widen this, but exposing `venue_api` would put it on
REST. The owner chose to fix it before exposure (V-13, recorded in `docs/dashboards/OWNER_DECISIONS.md`
on #120).

176 keeps each public predicate and adds a published parent, using the rule that
`catalog_event_sel_anon` already applies (078):

```sql
-- venue_ticket_type_sel_public
using (visibility = 'public'
       and exists (select 1 from catalog.event e
                    where e.event_id = venue.ticket_type.event_id
                      and e.status <> 'draft'))
-- venue_inventory_batch_sel_public
using (exists (select 1 from venue.ticket_type tt
                 join catalog.event e on e.event_id = tt.event_id
                where tt.ticket_type_id = venue.inventory_batch.ticket_type_id
                  and tt.visibility = 'public'
                  and e.status <> 'draft'))
```

- **The test is `status <> 'draft'`, never `>= 'announced'` (R3-3a).** `status` is text, so `>=` compares
  alphabetically, and `'announced'` sorts first. Announced, on_sale, live, completed and cancelled
  events keep their public rows, exactly as `catalog.event` keeps those events visible. 246 B3, B4 and
  B7 prove the equivalence.
- **The batch resolves its event through its ticket type**, as both 081 batch arms do. Its session
  belongs to the same event: `create_inventory_batch` refuses `type_session_event_mismatch`, it is the
  only insert path, and nothing updates `ticket_type_id` or `event_session_id`.
- **These stay the same:** policy names, `FOR SELECT`, `TO authenticated`, `PERMISSIVE`, both
  `_sel_venue` arms, every grant (including the E-29 counter columns), RLS enablement and every
  function. 246 A1–A3, A5–A7, P3 and P4 check all of these.
- **No recursion.** The parent check is an inline `EXISTS`, the 078 pattern
  (`catalog_event_session_sel_anon`, `catalog_resale_policy_sel_public`), and adds no definer helper.
  `catalog.event`'s policies call only definer helpers over `org_member`, `platform_role` and
  `staff_role`, so nothing reads back into `venue.*`. Because `e.status <> 'draft'` is written out, the
  result does not depend on which `catalog.event` arm made the row visible. No function is created,
  so no `search_path` question arises.

## 2. Readers: summary (full list in `176_READERS.md`)

- **Changed (intended):** direct reads of the two tables by signed-in callers, and the two `venue_api`
  views, which equal the base tables.
- **Lose a draft's public type and batch:** every signed-in caller with no grant on that event. That
  covers fans, outsiders, staff of other venues, org_marketing, org_promoter_manager and the platform
  labels.
- **Keep a draft's types but lose its batches:** org_member, venue_box_office, venue_marketing and
  venue_promoter_manager. None of them is in 081's batch arm, so the public arm was their only path.
  Only org_member can open a draft event at all. In D's venue app, its draft inventory list becomes
  empty, which D should present as "availability appears after publish".
- **Unchanged:** venue_manager, org_owner and org_admin (everything), and org_finance, venue_finance
  and venue_scanner (non-hidden types and their batches). anon stays behind the schema wall.
- **Unaffected:** all 20 `SECURITY DEFINER` readers (checkout, publish, comps, market, promoter,
  `get_my_tickets`, …), the primary-checkout edge function, `web/`, `admin/`, the mobile venue client
  (not wired, schema not exposed), D's acceptance kit (no draft-event ticket types in its fixtures)
  and pgTAP 145, 147, 148, 149, 153 and 226.
- **Four-file rule:** no row is needed. The Gate-2 census counts `schemaname = 'public'` only, and that
  includes `EXPECT_POLICIES` in `ci.yml`. `expected_grants.txt`, the grant-decision manifest and
  `parity_grants.sql` are also `public` only. No table or function is added. pgTAP 246 is the gate for
  the four policy definitions. The coverage floors in `ci.yml` are `>=`, so a new file needs no edit
  there.

## 3. Order

| Step | Constraint |
|---|---|
| merge and apply | after **159** (`20261021120000`) and A's **173–175** (`20261021133000`, `…134000`, `…135000`); before **177** (`20261022001000`) and **178** (`20261022002000`). Migrations-guard rule 4 requires 176 to sort above the base's latest migration, and A re-timestamps if the order changes |
| exposure | 176 must be applied on a project **before** the owner adds `venue_api` to that project's Data API exposed schemas (159 doc §7 step 4). Until then, no REST path to the leak exists: `venue` and `venue_api` are not exposed (last recorded list: `public, graphql_public, kernel, ops`, 2026-09-08) |
| production venue | if the owner's pop-up venue gets a **draft** event with public ticket types before 176 applies, nothing leaks while `venue_api` is not exposed. Do not expose `venue_api` until 176 is applied and V1 has passed |

176 has no object in common with 157, 158 or 170–175. None of them touches `venue` or `catalog`.

## 4. Rollback

`supabase/rollbacks/20261022000000_venue_public_arms_require_published_event_rollback.sql` restores
081's two public arms byte for byte. It is idempotent and touches nothing else. **It reopens the draft
read**, so remove `venue_api` from the exposed schemas first, or have the owner accept the exposure
explicitly. Use it only if P0 showed 081's text on that project (otherwise it does not restore that
project's prior state: stop and ask A). The ledger row is a separate, owner-authorised step. Run it
only under owner approval.

## 5. Verification (read-only, as `postgres` in the SQL editor)

```sql
-- P0  PRE-APPLY. Four rows. Record the md5 column.
--     Expected before 176: has_draft_conjunct = f on both *_sel_public rows (081's text);
--     roles {authenticated}, cmd SELECT, permissive PERMISSIVE, with_check NULL on all four.
select tablename, policyname, roles, cmd, permissive, with_check,
       position('<> ''draft''' in qual) > 0 as has_draft_conjunct,
       md5(qual) as qual_md5,
       regexp_replace(qual, '\s+', ' ', 'g') as qual_normalized
  from pg_policies
 where schemaname = 'venue' and tablename in ('ticket_type', 'inventory_batch')
 order by tablename, policyname;

-- P0b PRE-APPLY exposure size: draft-event public rows that any signed-in user can read today.
select (select count(*) from venue.ticket_type t join catalog.event e on e.event_id = t.event_id
         where e.status = 'draft' and t.visibility = 'public') as draft_public_types,
       (select count(*) from venue.inventory_batch b
          join venue.ticket_type t on t.ticket_type_id = b.ticket_type_id
          join catalog.event e on e.event_id = t.event_id
         where e.status = 'draft' and t.visibility = 'public') as draft_public_batches;

-- V1  POST-APPLY: the P0 query again. Expected:
--     *_sel_public: has_draft_conjunct = t, qual has no '>=', roles {authenticated}, SELECT, PERMISSIVE, with_check NULL;
--     *_sel_venue:  qual_md5 IDENTICAL to the P0 values (unchanged arms).
--     Predicted normalized quals (from reading the deparser, to be confirmed on the first replay):
--       ((visibility = 'public'::text) AND (EXISTS ( SELECT 1 FROM catalog.event e WHERE ((e.event_id = ticket_type.event_id) AND (e.status <> 'draft'::text)))))
--       (EXISTS ( SELECT 1 FROM (venue.ticket_type tt JOIN catalog.event e ON ((e.event_id = tt.event_id))) WHERE ((tt.ticket_type_id = inventory_batch.ticket_type_id) AND (tt.visibility = 'public'::text) AND (e.status <> 'draft'::text))))

-- V2  POST-APPLY ledger row (only if the apply wrote one):
select version, name from supabase_migrations.schema_migrations where version = '20261022000000';

-- V3  POST-APPLY: P0b again. The counts are informational (176 changes no rows); they say how many
--     rows are now hidden from callers without a grant.
```

## 6. Owner and A steps

1. **A reviews this branch** before it leaves draft: an independent replay, pgTAP 246, the §7 mutants,
   the rollback cycle, and §8 of `176_READERS.md`. A then decides whether the four roles that lose
   draft batches (§2) are acceptable or need a separate change. This doc assumes they are acceptable,
   because the `_sel_venue` arms were to stay unchanged.
2. **Draft PR** against the integration base A names. It is migration-bearing, so the description
   carries `AUTODEPLOY-VERIFIED-OFF: YYYY-MM-DD` from the owner's attestation, which A holds. It merges
   after 159 and 173–175 are in that base and before 177 and 178.
3. **The owner authorises each apply** (sandbox first, then production). Each apply is a targeted
   single-file apply plus its ledger row, never `db push`. Run P0 and P0b immediately before, and V1–V3
   after. Any difference from §5 means STOP: report to A, and do not patch in place.
4. **Only then** comes the `venue_api` exposure step (159 doc §7 step 4), whose exposure finding 176
   resolves.
5. **D**: in the venue app, show an org_member's empty draft inventory as "availability appears after
   publish". Optionally, add an outsider check to the acceptance kit: a draft's public type is absent.
   New Party Pass readers follow `176_READERS.md` §6.

## 7. Runs owed (heavy slot), with predictions

| Run | Expected |
|---|---|
| Fresh replay, Supabase CLI 2.115.0, base + 176 | every migration applies. The post-condition `DO` block passes. Gate-2 counts are unchanged at `35\|126\|37\|49` |
| pgTAP 246 on base + 176 | 50/50 |
| **RED:** pgTAP 246 on the base without 176 | exactly A4, B1, B2, B7, B8, B9, B10, B11, B12, D1, D2, E8, E11, P1 and P2 fail (15). The other 35 pass |
| pgTAP 145, 226, 147, 148, 149 and 153 on base + 176 | unchanged green (145 A20 keeps the names) |
| Full suite and the CI planned-vs-ran check | the plan total rises by 50. The file contains exactly one `plan(` |
| Rollback cycle: apply 176, run the rollback, run 246, re-apply, run 246 | after the rollback, the RED set above. After the re-apply, 50/50. The `_sel_venue` md5s stay identical throughout |
| M1: `e.status >= 'announced'` in the type arm | A4, B1, B7, B9, B11, D1, P1. The batch rows stay green, because the batch arm carries its own conjunct |
| M2: the batch arm reverted to 081's body (type arm fixed) | A4, E8, E11, P2. The outsider rows stay green, because 081's batch arm reads `venue.ticket_type` under the caller's RLS, which now hides the draft type. org_member and venue_box_office still read that type through `_sel_venue`, so only their rows catch it |
| M3: `e.status in ('on_sale','live')` in both arms | A4, B3, B4, B7, B8, P1, P2 |
| M4: the type arm keeps the event check but drops `visibility = 'public'` | B5, B13 (the outsider would see hidden and door_only types), P1 |
| M5: the type arm made `AS RESTRICTIVE` | A2 and most behaviour rows (B3, B7, B13, D3, E1, E3, E5, E7, E10, F1, …) |
| M6: the type arm `TO anon, authenticated` | A2 |
| M7: the batch arm resolved through `event_session_id` instead of the type | P2 only (the same event by invariant; the pin is what catches it) |
| M8: a stray change to `venue_ticket_type_sel_venue` (e.g. the `visibility <> 'hidden'` tier dropped) | P3, E5, E6, E7, E10 |

## Local rehearsal (2026-10-22, Homebrew PostgreSQL 17, localhost:5432)
Base: a fresh replay of `venue/api-read-views-provisional` @ 8ccb26e1 (172 migrations, through 159), built as `postgres` so the 156 proof-guard bypass fires in the seed. Logs: `private-evidence/F-web-redesign/logs/round2-gates/mig176/` (SSD, private).
- Control: pgTAP 226 on the base, 72/72.
- RED, base without 176: 246 plan 50, ok 35, not_ok 15 — exactly A4 B1 B2 B7 B8 B9 B10 B11 B12 D1 D2 E8 E11 P1 P2 (the predicted set).
- Apply 176: exit 0. GREEN: 50/50.
- Mutants M1–M8 (restore.sql between runs): every one fails 246 (not_ok 2 / 4 / 7 / 3 / 19 / 1 / 1 / 5). Restored: 50/50 again.
- Rollback: exit 0; `pg_policies` md5(qual) for both public arms returns to the 081 values (`c2960bb8…` ticket_type, `898e6aa6…` inventory_batch), the same md5s the base showed before apply.
- Harness note: a base replayed as the OS user has `postgres`-only bypasses in definer bodies that never fire, so even 226 fails at `tap.seed_core` with "Upload proof of ownership." Replay as `postgres`.
