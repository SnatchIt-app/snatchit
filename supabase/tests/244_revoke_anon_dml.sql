-- ============================================================================
-- 244_revoke_anon_dml.sql — registry 174 (20261021134000_revoke_anon_dml.sql).
--
-- anon (the signed-out PostgREST role) held INSERT/UPDATE/DELETE on 14 public tables that no client of any
-- age writes while signed out (bids, disputes, listings, notification_preferences, payments, payout_decisions,
-- payout_policy, push_tokens, reports, saved_listings, seller_flags, seller_risk_scores, stripe_connect_archive,
-- user_blocks): only RLS refused them. 174 revokes exactly those privileges; RLS stays.
-- The three signed-out website forms (ambassador_applications, investor_leads, venue_partnership_inquiries) keep
-- their anon grants exactly as they are.
--
-- Tags: [PKG] fails without 174 (on a production-equivalent database AND on the CI replay + parity_grants.sql
-- before 174's parity edit), passes with it; [CTRL] passes in both states (what 174 must not change).
-- Every assertion is environment-neutral: has_table_privilege / has_any_column_privilege, never a relacl literal
-- (production carries MAINTAIN 'm' on these entries; the CI parity bootstrap does not grant it).
-- R2 / R5.1 sweep every public relation kind but skip extension members (pg_depend deptype 'e'): pgTAP itself lives
-- in public here and its views (pg_all_foreign_keys, tap_funky) inherit the public default ACL on a Supabase stack.
--   R1  per table: anon holds no write-class privilege, table or column level            [PKG] x14
--   R2  the public tables anon may write are exactly the three website forms              [PKG]
--   R3  every anon INSERT / UPDATE / DELETE on the 14 is refused by the GRANT: SQLSTATE 42501 with
--       'permission denied for table <t>', not an RLS refusal or a silent zero-row success  [PKG] x41, [CTRL] x1
--   R4  website forms: anon INSERT of the real website payload still succeeds; grants intact [CTRL]
--   R5  anon keeps its read surface (SELECT grants, browsing)                              [CTRL]
--   R6  authenticated and service_role privileges on the 14 are unchanged                  [CTRL]
--   R7  signed-in writes the current clients make still work                               [CTRL]
-- Synthetic fixtures only (tap.seed_core); everything dies with the ROLLBACK.
-- ============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(73);
SELECT tap.seed_core();

-- anon's write-class privileges on a relation, table level plus column level, sorted; '' when none.
CREATE FUNCTION tap._w174_anon_writes(p regclass) RETURNS text LANGUAGE sql STABLE AS $f$
  SELECT coalesce(string_agg(x, ',' ORDER BY x), '')
    FROM unnest(ARRAY['DELETE','INSERT','REFERENCES','TRIGGER','TRUNCATE','UPDATE']) AS x
   WHERE has_table_privilege('anon', p, x)
      OR (x IN ('INSERT','UPDATE','REFERENCES') AND has_any_column_privilege('anon', p, x))
$f$;
-- run a count query as the CURRENT role; -1 when the role lacks the privilege (so a planted over-revoke reports
-- 'not ok' instead of aborting the transaction and every assertion after it).
CREATE FUNCTION tap._w174_try(q text) RETURNS bigint LANGUAGE plpgsql AS $f$
DECLARE c bigint;
BEGIN
  EXECUTE q INTO c;
  RETURN c;
EXCEPTION WHEN insufficient_privilege THEN
  RETURN -1;
END $f$;
-- a role's standard table privileges on a relation, sorted.
CREATE FUNCTION tap._w174_privs(r text, p regclass) RETURNS text LANGUAGE sql STABLE AS $f$
  SELECT coalesce(string_agg(x, ',' ORDER BY x), '')
    FROM unnest(ARRAY['DELETE','INSERT','REFERENCES','SELECT','TRIGGER','TRUNCATE','UPDATE']) AS x
   WHERE has_table_privilege(r, p, x)
$f$;

-- ── R1. per table: no anon write privilege ─────────────────────────────────
SELECT is(tap._w174_anon_writes('public.bids'),                     '', 'R1.1 [PKG] anon holds no write privilege on public.bids');
SELECT is(tap._w174_anon_writes('public.disputes'),                 '', 'R1.2 [PKG] anon holds no write privilege on public.disputes');
SELECT is(tap._w174_anon_writes('public.listings'),                 '', 'R1.3 [PKG] anon holds no write privilege on public.listings');
SELECT is(tap._w174_anon_writes('public.notification_preferences'), '', 'R1.4 [PKG] anon holds no write privilege on public.notification_preferences');
SELECT is(tap._w174_anon_writes('public.payments'),                 '', 'R1.5 [PKG] anon holds no write privilege on public.payments');
SELECT is(tap._w174_anon_writes('public.payout_decisions'),         '', 'R1.6 [PKG] anon holds no write privilege on public.payout_decisions');
SELECT is(tap._w174_anon_writes('public.payout_policy'),            '', 'R1.7 [PKG] anon holds no write privilege on public.payout_policy');
SELECT is(tap._w174_anon_writes('public.push_tokens'),              '', 'R1.8 [PKG] anon holds no write privilege on public.push_tokens');
SELECT is(tap._w174_anon_writes('public.reports'),                  '', 'R1.9 [PKG] anon holds no write privilege on public.reports');
SELECT is(tap._w174_anon_writes('public.saved_listings'),           '', 'R1.10 [PKG] anon holds no write privilege on public.saved_listings');
SELECT is(tap._w174_anon_writes('public.seller_flags'),             '', 'R1.11 [PKG] anon holds no write privilege on public.seller_flags');
SELECT is(tap._w174_anon_writes('public.seller_risk_scores'),       '', 'R1.12 [PKG] anon holds no write privilege on public.seller_risk_scores');
SELECT is(tap._w174_anon_writes('public.stripe_connect_archive'),   '', 'R1.13 [PKG] anon holds no write privilege on public.stripe_connect_archive');
SELECT is(tap._w174_anon_writes('public.user_blocks'),              '', 'R1.14 [PKG] anon holds no write privilege on public.user_blocks');

-- ── R2. the whole schema: anon may write only the three signed-out website forms ─
SELECT is(
  (SELECT string_agg(c.relname, ',' ORDER BY c.relname)
     FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind IN ('r','p','v','m','f')
      AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid = 'pg_class'::regclass AND d.objid = c.oid AND d.deptype = 'e')
      AND tap._w174_anon_writes(c.oid) <> ''),
  'ambassador_applications,investor_leads,venue_partnership_inquiries',
  'R2 [PKG] the public relations anon may write (table or column level) are exactly the three website forms');

-- ── R3. as anon: every write is a GRANT refusal (42501 permission denied), never RLS or 0 rows ─
SELECT tap.login_anon();
SELECT throws_ok($$ INSERT INTO public.bids DEFAULT VALUES $$,                        '42501', 'permission denied for table bids',                     'R3.1 [PKG] anon INSERT bids: permission denied (was the bid trigger / RLS)');
SELECT throws_ok($$ UPDATE public.bids SET id = id $$,                                 '42501', 'permission denied for table bids',                     'R3.2 [PKG] anon UPDATE bids: permission denied (was a silent 0-row success)');
SELECT throws_ok($$ DELETE FROM public.bids $$,                                        '42501', 'permission denied for table bids',                     'R3.3 [PKG] anon DELETE bids: permission denied (was a silent 0-row success)');
SELECT throws_ok($$ INSERT INTO public.disputes DEFAULT VALUES $$,                    '42501', 'permission denied for table disputes',                 'R3.4 [PKG] anon INSERT disputes: permission denied (was RLS)');
SELECT throws_ok($$ UPDATE public.disputes SET id = id $$,                             '42501', 'permission denied for table disputes',                 'R3.5 [PKG] anon UPDATE disputes: permission denied');
SELECT throws_ok($$ DELETE FROM public.disputes $$,                                    '42501', 'permission denied for table disputes',                 'R3.6 [PKG] anon DELETE disputes: permission denied');
SELECT throws_ok($$ INSERT INTO public.listings DEFAULT VALUES $$,                    '42501', 'permission denied for table listings',                 'R3.7 [PKG] anon INSERT listings: permission denied (was the policy''s phone_verified() EXECUTE refusal)');
SELECT throws_ok($$ UPDATE public.listings SET id = id $$,                             '42501', 'permission denied for table listings',                 'R3.8 [PKG] anon UPDATE listings: permission denied (was a silent 0-row success)');
SELECT throws_ok($$ DELETE FROM public.listings $$,                                    '42501', 'permission denied for table listings',                 'R3.9 [PKG] anon DELETE listings: permission denied (was a silent 0-row success)');
SELECT throws_ok($$ INSERT INTO public.notification_preferences DEFAULT VALUES $$,    '42501', 'permission denied for table notification_preferences', 'R3.10 [PKG] anon INSERT notification_preferences: permission denied (was RLS)');
SELECT throws_ok($$ UPDATE public.notification_preferences SET user_id = user_id $$,   '42501', 'permission denied for table notification_preferences', 'R3.11 [PKG] anon UPDATE notification_preferences: permission denied');
SELECT throws_ok($$ DELETE FROM public.notification_preferences $$,                    '42501', 'permission denied for table notification_preferences', 'R3.12 [PKG] anon DELETE notification_preferences: permission denied');
SELECT throws_ok($$ INSERT INTO public.payments DEFAULT VALUES $$,                    '42501', 'permission denied for table payments',                 'R3.13 [PKG] anon INSERT payments: permission denied (was RLS)');
SELECT throws_ok($$ UPDATE public.payments SET id = id $$,                             '42501', 'permission denied for table payments',                 'R3.14 [PKG] anon UPDATE payments: permission denied');
SELECT throws_ok($$ DELETE FROM public.payments $$,                                    '42501', 'permission denied for table payments',                 'R3.15 [PKG] anon DELETE payments: permission denied');
SELECT throws_ok($$ INSERT INTO public.payout_decisions DEFAULT VALUES $$,            '42501', 'permission denied for table payout_decisions',         'R3.16 [PKG] anon INSERT payout_decisions: permission denied (was RLS)');
SELECT throws_ok($$ UPDATE public.payout_decisions SET id = id $$,                     '42501', 'permission denied for table payout_decisions',         'R3.17 [PKG] anon UPDATE payout_decisions: permission denied');
SELECT throws_ok($$ DELETE FROM public.payout_decisions $$,                            '42501', 'permission denied for table payout_decisions',         'R3.18 [PKG] anon DELETE payout_decisions: permission denied');
SELECT throws_ok($$ INSERT INTO public.payout_policy DEFAULT VALUES $$,               '42501', 'permission denied for table payout_policy',            'R3.19 [PKG] anon INSERT payout_policy: permission denied (was RLS)');
SELECT throws_ok($$ UPDATE public.payout_policy SET id = id $$,                        '42501', 'permission denied for table payout_policy',            'R3.20 [PKG] anon UPDATE payout_policy: permission denied');
SELECT throws_ok($$ DELETE FROM public.payout_policy $$,                               '42501', 'permission denied for table payout_policy',            'R3.21 [PKG] anon DELETE payout_policy: permission denied');
SELECT throws_ok($$ INSERT INTO public.push_tokens DEFAULT VALUES $$,                 '42501', 'permission denied for table push_tokens',              'R3.22 [PKG] anon INSERT push_tokens: permission denied (was RLS)');
SELECT throws_ok($$ UPDATE public.push_tokens SET id = id $$,                          '42501', 'permission denied for table push_tokens',              'R3.23 [CTRL] anon UPDATE push_tokens: permission denied (anon never held UPDATE; unchanged)');
SELECT throws_ok($$ DELETE FROM public.push_tokens $$,                                 '42501', 'permission denied for table push_tokens',              'R3.24 [PKG] anon DELETE push_tokens: permission denied (was a silent 0-row success)');
SELECT throws_ok($$ INSERT INTO public.reports DEFAULT VALUES $$,                     '42501', 'permission denied for table reports',                  'R3.25 [PKG] anon INSERT reports: permission denied (was RLS)');
SELECT throws_ok($$ UPDATE public.reports SET id = id $$,                              '42501', 'permission denied for table reports',                  'R3.26 [PKG] anon UPDATE reports: permission denied');
SELECT throws_ok($$ DELETE FROM public.reports $$,                                     '42501', 'permission denied for table reports',                  'R3.27 [PKG] anon DELETE reports: permission denied');
SELECT throws_ok($$ INSERT INTO public.saved_listings DEFAULT VALUES $$,              '42501', 'permission denied for table saved_listings',           'R3.28 [PKG] anon INSERT saved_listings: permission denied (was RLS)');
SELECT throws_ok($$ UPDATE public.saved_listings SET id = id $$,                       '42501', 'permission denied for table saved_listings',           'R3.29 [PKG] anon UPDATE saved_listings: permission denied');
SELECT throws_ok($$ DELETE FROM public.saved_listings $$,                              '42501', 'permission denied for table saved_listings',           'R3.30 [PKG] anon DELETE saved_listings: permission denied');
SELECT throws_ok($$ INSERT INTO public.seller_flags DEFAULT VALUES $$,                '42501', 'permission denied for table seller_flags',             'R3.31 [PKG] anon INSERT seller_flags: permission denied (was RLS)');
SELECT throws_ok($$ UPDATE public.seller_flags SET id = id $$,                         '42501', 'permission denied for table seller_flags',             'R3.32 [PKG] anon UPDATE seller_flags: permission denied');
SELECT throws_ok($$ DELETE FROM public.seller_flags $$,                                '42501', 'permission denied for table seller_flags',             'R3.33 [PKG] anon DELETE seller_flags: permission denied');
SELECT throws_ok($$ INSERT INTO public.seller_risk_scores DEFAULT VALUES $$,          '42501', 'permission denied for table seller_risk_scores',       'R3.34 [PKG] anon INSERT seller_risk_scores: permission denied (was RLS)');
SELECT throws_ok($$ UPDATE public.seller_risk_scores SET seller_id = seller_id $$,     '42501', 'permission denied for table seller_risk_scores',       'R3.35 [PKG] anon UPDATE seller_risk_scores: permission denied');
SELECT throws_ok($$ DELETE FROM public.seller_risk_scores $$,                          '42501', 'permission denied for table seller_risk_scores',       'R3.36 [PKG] anon DELETE seller_risk_scores: permission denied');
SELECT throws_ok($$ INSERT INTO public.stripe_connect_archive DEFAULT VALUES $$,      '42501', 'permission denied for table stripe_connect_archive',   'R3.37 [PKG] anon INSERT stripe_connect_archive: permission denied (was RLS)');
SELECT throws_ok($$ UPDATE public.stripe_connect_archive SET id = id $$,               '42501', 'permission denied for table stripe_connect_archive',   'R3.38 [PKG] anon UPDATE stripe_connect_archive: permission denied');
SELECT throws_ok($$ DELETE FROM public.stripe_connect_archive $$,                      '42501', 'permission denied for table stripe_connect_archive',   'R3.39 [PKG] anon DELETE stripe_connect_archive: permission denied');
SELECT throws_ok($$ INSERT INTO public.user_blocks DEFAULT VALUES $$,                 '42501', 'permission denied for table user_blocks',              'R3.40 [PKG] anon INSERT user_blocks: permission denied (was RLS)');
SELECT throws_ok($$ UPDATE public.user_blocks SET blocker_id = blocker_id $$,          '42501', 'permission denied for table user_blocks',              'R3.41 [PKG] anon UPDATE user_blocks: permission denied');
SELECT throws_ok($$ DELETE FROM public.user_blocks $$,                                 '42501', 'permission denied for table user_blocks',              'R3.42 [PKG] anon DELETE user_blocks: permission denied');

-- ── R4. the signed-out website forms keep working, exactly as before ────────
-- The website posts with Prefer: return=minimal, i.e. a plain INSERT as anon (no RETURNING).
SELECT lives_ok($$ INSERT INTO public.investor_leads (full_name, email, company, message, source)
                   VALUES ('W174 Probe', 'w174-investor@example.invalid', 'Probe Co', 'probe', 'website') $$,
  'R4.1 [CTRL] anon INSERT of the website investor form payload still succeeds');
SELECT lives_ok($$ INSERT INTO public.ambassador_applications (full_name, email, phone, city, country, age_confirmed,
                     ambassador_category, audience_size_range, audience_location, content_focus, audience_channels,
                     motivation, promotion_plan, terms_accepted, contact_consent)
                   VALUES ('W174 Probe', 'w174-ambassador@example.invalid', '+10000000000', 'Miami', 'US', true,
                     'promoter', '1k_10k', 'Miami', 'nightlife', '{instagram}', 'probe', 'probe', true, true) $$,
  'R4.2 [CTRL] anon INSERT of the website ambassador form payload still succeeds');
SELECT lives_ok($$ INSERT INTO public.venue_partnership_inquiries (full_name, work_email, phone, company_name,
                     venue_or_event_name, city, venue_or_event_type, partnership_interest, source)
                   VALUES ('W174 Probe', 'w174-venue@example.invalid', '+10000000000', 'Probe Co', 'Probe Venue',
                     'Miami', 'nightclub', 'official_resale', 'venues_page') $$,
  'R4.3 [CTRL] anon INSERT of the website venue inquiry payload still succeeds');
SELECT is(tap._w174_try($$ WITH u AS (UPDATE public.investor_leads SET message = 'x' RETURNING 1) SELECT count(*) FROM u $$),
  0::bigint, 'R4.4 [CTRL] anon UPDATE on a website-form table is still the RLS zero-row refusal (grants untouched)');
SELECT tap.logout();
SELECT is(
  (SELECT count(*) FROM public.investor_leads WHERE email = 'w174-investor@example.invalid')
  + (SELECT count(*) FROM public.ambassador_applications WHERE email = 'w174-ambassador@example.invalid')
  + (SELECT count(*) FROM public.venue_partnership_inquiries WHERE work_email = 'w174-venue@example.invalid'),
  3::bigint, 'R4.5 [CTRL] the three anon website submissions landed');
SELECT is(
  (SELECT string_agg(t || ':' || tap._w174_privs('anon', ('public.' || t)::regclass), ' ' ORDER BY t)
     FROM unnest(ARRAY['ambassador_applications','investor_leads','venue_partnership_inquiries']) AS t),
  'ambassador_applications:DELETE,INSERT,SELECT,UPDATE investor_leads:DELETE,INSERT,SELECT,UPDATE venue_partnership_inquiries:DELETE,INSERT,SELECT,UPDATE',
  'R4.6 [CTRL] the website-form tables keep exactly their anon grants');

-- ── R5. anon keeps its read surface ────────────────────────────────────────
SELECT is(
  (SELECT string_agg(c.relname, ',' ORDER BY c.relname)
     FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind IN ('r','p','v','m','f')
      AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid = 'pg_class'::regclass AND d.objid = c.oid AND d.deptype = 'e')
      AND has_table_privilege('anon', c.oid, 'SELECT')),
  'ambassador_applications,bids,disputes,investor_leads,listings,notification_preferences,payments,payout_decisions,'
  || 'payout_policy,reports,saved_listings,seller_flags,seller_risk_scores,stripe_connect_archive,transfers,user_blocks,'
  || 'venue_partnership_inquiries',
  'R5.1 [CTRL] the public tables anon may SELECT are unchanged (174 revokes no SELECT)');
SELECT tap.login_anon();
SELECT is(tap._w174_try($$ SELECT count(*) FROM public.listings WHERE id = tap.listing_a() $$), 1::bigint,
  'R5.2 [CTRL] anon still browses a public listing');
SELECT lives_ok($$ SELECT amount FROM public.bids WHERE listing_id = tap.listing_a() $$,
  'R5.3 [CTRL] anon still reads the bids of a public listing');
SELECT tap.logout();

-- ── R6. authenticated and service_role privileges on the 14 are untouched ───
SELECT is(
  (SELECT string_agg(t || ':' || tap._w174_privs('authenticated', ('public.' || t)::regclass), ' ' ORDER BY t)
     FROM unnest(ARRAY['bids','disputes','listings','notification_preferences','payments','payout_decisions','payout_policy',
                       'push_tokens','reports','saved_listings','seller_flags','seller_risk_scores','stripe_connect_archive',
                       'user_blocks']) AS t),
  'bids:DELETE,INSERT,SELECT,UPDATE disputes:DELETE,INSERT,SELECT,UPDATE listings:DELETE,INSERT,SELECT,UPDATE '
  || 'notification_preferences:DELETE,INSERT,SELECT,UPDATE payments:DELETE,INSERT,SELECT,UPDATE '
  || 'payout_decisions:DELETE,INSERT,SELECT,UPDATE payout_policy:DELETE,INSERT,SELECT,UPDATE push_tokens:DELETE,INSERT '
  || 'reports:DELETE,INSERT,SELECT,UPDATE saved_listings:DELETE,INSERT,SELECT,UPDATE seller_flags:DELETE,INSERT,SELECT,UPDATE '
  || 'seller_risk_scores:DELETE,INSERT,SELECT,UPDATE stripe_connect_archive:DELETE,INSERT,SELECT,UPDATE '
  || 'user_blocks:DELETE,INSERT,SELECT,UPDATE',
  'R6.1 [CTRL] authenticated keeps exactly its table privileges on the 14 tables');
SELECT ok(
  (SELECT bool_and(tap._w174_privs('service_role', ('public.' || t)::regclass) = 'DELETE,INSERT,REFERENCES,SELECT,TRIGGER,TRUNCATE,UPDATE')
     FROM unnest(ARRAY['bids','disputes','listings','notification_preferences','payments','payout_decisions','payout_policy',
                       'push_tokens','reports','saved_listings','seller_flags','seller_risk_scores','stripe_connect_archive',
                       'user_blocks']) AS t),
  'R6.2 [CTRL] service_role keeps all seven table privileges on the 14 tables');

-- ── R7. the signed-in writes the current clients make still work ────────────
SELECT tap.login(tap.buyer());
SELECT lives_ok($$ INSERT INTO public.bids (listing_id, bidder_id, amount) VALUES (tap.listing_a(), tap.buyer(), 150) $$,
  'R7.1 [CTRL] a signed-in bidder still bids by direct INSERT (PlaceBidScreen / web bids.ts)');
SELECT lives_ok($$ UPDATE public.notification_preferences SET notify_outbid = false WHERE user_id = tap.buyer() $$,
  'R7.2 [CTRL] a signed-in user still updates their own notification preferences');
SELECT lives_ok($$ INSERT INTO public.user_blocks (blocker_id, blocked_id) VALUES (tap.buyer(), tap.other_user()) $$,
  'R7.3 [CTRL] a signed-in user still blocks another user');
SELECT tap.login(tap.seller());
SELECT lives_ok($$ DELETE FROM public.listings WHERE id = tap.listing_c() AND seller_id = tap.seller() $$,
  'R7.4 [CTRL] a seller still deletes their own no-activity listing (my-listings / seller-listings)');
SELECT tap.logout();
SELECT is(
  (SELECT count(*) FROM public.bids WHERE listing_id = tap.listing_a() AND bidder_id = tap.buyer() AND amount = 150)
  + (SELECT count(*) FROM public.notification_preferences WHERE user_id = tap.buyer() AND notify_outbid = false)
  + (SELECT count(*) FROM public.user_blocks WHERE blocker_id = tap.buyer() AND blocked_id = tap.other_user())
  + (SELECT 1 - count(*) FROM public.listings WHERE id = tap.listing_c()),
  4::bigint, 'R7.5 [CTRL] the four signed-in writes took effect (bid row, preference, block, listing gone)');

SELECT * FROM finish();
ROLLBACK;
