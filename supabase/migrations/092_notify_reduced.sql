-- ============================================================================
-- 092_notify_reduced.sql — Phase-2 package 092 — THE FINAL PACKAGE OF THE
-- 076–092 TRAIN. Gate P REDUCED notification plane + the outbox drainer.
-- Authorities: registry §2 row 092 (OR-12 · ODR1_AMENDMENT_DRAFT §6.2) ·
-- OR-5 [C] (scope) · OR-14 (R2 two emit behaviours; R2_EMITTER_CLASSIFICATION
-- normative) · OR-15 / OR-17 (the reduced IN set is 31) · NOTIF §2 (catalogue)
-- §3 (registry + sparse override + DDL mandatory guard) §4 (pipeline, three
-- idempotency keys) §5 (templates, locale) §6 (schema/RLS/RPC deltas) §8
-- (privacy) §9 (assertions) · RPC §17.24 (the reduced 16-RPC surface IS
-- authority to build) §17.25 (claim/record contracts) · RLS §16.9 · §11 notify
-- rows · WRITER_REGISTRY notify rows · CRON_SCHEDULE_REGISTER 092 rows · schema
-- §13.4 (push_tokens +4, extend not replace) · DSM §3.1.4/§4.7 (deletion
-- notices) · E-152…E-160 (this package, governance register).
-- ----------------------------------------------------------------------------
-- THE CLOSED WORLD (repository bytes over the prompt):
--   TABLES (6): notify.notification_type · notification · delivery · preference
--     · template · identity_channel_state.  NOT: notify.schedule, notify.
--     announcement (dropped by OR-5), notify.outbox (076).
--   ADDITIVE COLUMNS: notify.outbox.expand_cursor / expanded_count (§17.24
--     bounded-expansion obligation, mechanism (i)); public.push_tokens
--     revoked_at / revoked_reason / provider_receipt_checked_at /
--     last_provider_error (schema §13.4, O-N11: extend, never a second table).
--   FUNCTIONS (15 = the reduced 16 minus emit_event which lives in 076):
--     internal DEF (service_role): drain_outbox · enqueue · channel_enabled ·
--     claim_deliveries · record_delivery_result · resolve_web_link; consumer
--     (authenticated, auth.uid()-scoped): get_inbox · get_unread_count ·
--     mark_read · mark_all_read · dismiss · get_preference_matrix ·
--     set_preference · register_push_token · revoke_push_token.
--   SEEDS: 31 notification_type rows (the OR-15/OR-17 reduced IN set) + their
--     in_app and push templates (en-US, version 1). NO email templates (N1 —
--     email does not exist; E rows are born `suppressed / channel_unavailable`,
--     NOTIF §2.1 verbatim). NO legacy rows (ODR-114 silence → leave alongside).
--   CRON (1 of the register's 3): notify-drain-outbox */2. The two edge ticks
--     (notify-dispatch 1 min, notify-receipts 15 min) are DEPLOY ARTIFACTS whose
--     dedicated-header and Vault-secret NAMES no frozen byte supplies (E-79 /
--     RESALE_CHECKOUT_SWEEP_TICK class) — PARKED, recorded (E-158).
--   CONFIG: notify.delivery_lease_interval seeded NULL / owner-unset (PFA-22
--     shape; the key is frozen, its value is not) — claim_deliveries FAILS CLOSED.
--   SEAMS: none replaced, none added (19 hooks, all real, unchanged).
--   NO announcement surface, no schedule/sweep, no SMS, no localization
--   framework, no template CMS, no broker/bus/second queue (§6 of the prompt is
--   the OR-5 exclusion list and it holds).
--
-- REQUIRED vs BEST-EFFORT: the ENVELOPE write class is the producers' (OR-14;
-- 076 emit pair). This package is the CONSUMER side and is uniformly
-- best-effort: a failed fan-out never touches money/custody state (the outbox
-- row is quarantined `dead` with last_error — one bad row never blocks the
-- batch), delivery is at-least-once with idempotent logical notification
-- creation (three keys, three layers — NOTIF §4.2). NOT exactly-once on the
-- wire (the honest limit, §4.2/§17.25).
-- ============================================================================
begin;

-- ============================================================================
-- PART 1 — TABLES (NOTIF §3.2/§4.6/§5.2/§6.1; RLS §16.9)
-- ============================================================================
-- 1a — the C18 registry
create table if not exists notify.notification_type (
  type_key          text primary key,
  delivery_class    text not null check (delivery_class in ('mandatory','default_on','default_off')),
  allowed_channels  text[] not null check (allowed_channels <@ array['push','email']::text[]),
  default_channels  text[] not null check (default_channels <@ allowed_channels),
  target_kind       text not null,
  template_key      text not null,
  group_label       text not null,
  display_label     text not null,
  description       text,
  mandatory_reason  text,
  legacy            boolean not null default false,
  active            boolean not null default true,
  registry_version  integer not null default 1,
  created_at        timestamptz not null default now(),
  -- §3.3: the composite target of notify.preference's FK
  constraint notification_type_key_class_uq unique (type_key, delivery_class),
  constraint notification_type_mandatory_reason_ck check (delivery_class <> 'mandatory' or mandatory_reason is not null),
  -- N-DL-1 / N-A38: the closed target set, on the registry too
  constraint notification_type_target_ck check (target_kind in (
    'ticket','ticket_pass','event','event_session','listing','listing_native','p2p_transfer_in','p2p_transfer_out',
    'external_transfer_send','external_transfer_receive','order','refund','payout','account_security',
    'account_notifications','announcement','none'))
);

-- 1b — the durable record (040 posture verbatim — NOTIF §6.2)
create table if not exists notify.notification (
  notification_id uuid primary key default gen_random_uuid(),
  recipient_id    uuid not null references auth.users(id) on delete cascade,   -- §8.8: matches 040:67
  type_key        text not null references notify.notification_type(type_key) on delete restrict,
  template_key    text not null,
  params          jsonb not null default '{}'::jsonb,
  dedupe_key      text,                                                        -- hop-3 key (§4.2)
  subject_kind    text,
  subject_id      uuid,
  target_kind     text not null,
  target_id       uuid,
  locale_resolved text not null default 'en-US',
  -- legacy-shaped columns, always NULL for 092 producers (N-A36); kept so an
  -- ODR-114-ruled back-fill is additive. Bounds mirror 040.
  title           text check (title is null or char_length(title) <= 140),
  body            text check (body is null or char_length(body) <= 1000),
  link            text check (link is null or char_length(link) <= 2048),
  read_at         timestamptz,
  dismissed_at    timestamptz,
  -- clock_timestamp(), not now(): the inbox keyset (§6.3 get_inbox) is a single
  -- timestamptz cursor by frozen signature, and one drain tick writes hundreds
  -- of rows in ONE transaction — a shared now() would make them one keyset
  -- tie and a page boundary would skip rows (E-160).
  created_at      timestamptz not null default clock_timestamp(),
  constraint notification_target_ck check (target_kind in (
    'ticket','ticket_pass','event','event_session','listing','listing_native','p2p_transfer_in','p2p_transfer_out',
    'external_transfer_send','external_transfer_receive','order','refund','payout','account_security',
    'account_notifications','announcement','none'))
);
-- §4.2 hop 3: the exact 057:50-52 partial-unique pattern
create unique index if not exists notification_dedupe_key_uq on notify.notification (dedupe_key) where dedupe_key is not null;
create index if not exists notification_recipient_unread_idx on notify.notification (recipient_id, created_at desc) where read_at is null and dismissed_at is null;
create index if not exists notification_recipient_keyset_idx on notify.notification (recipient_id, created_at desc, notification_id desc);
create index if not exists notification_subject_idx on notify.notification (subject_kind, subject_id) where subject_id is not null;

-- 1c — per-(notification, channel) attempt state (§4.6; the delivery row IS the dead letter)
create table if not exists notify.delivery (
  delivery_id            uuid primary key default gen_random_uuid(),
  notification_id        uuid not null references notify.notification(notification_id) on delete cascade,
  channel                text not null check (channel in ('push','email')),
  state                  text not null default 'pending'
                         check (state in ('pending','claimed','sent','failed','dead','suppressed')),
  suppress_reason        text,
  attempt                integer not null default 0 check (attempt >= 0),
  next_attempt_at        timestamptz not null default now(),
  claimed_until          timestamptz,
  provider_message_id    text,
  provider_receipt_id    text,
  provider_receipt_state text,
  rendered_subject       text,
  rendered_body          text,
  last_error             text,
  sent_at                timestamptz,
  created_at             timestamptz not null default now(),
  constraint delivery_notification_channel_uq unique (notification_id, channel)     -- §4.2 hop 4
);
create index if not exists delivery_claim_idx on notify.delivery (channel, next_attempt_at) where state in ('pending','claimed');
create index if not exists delivery_receipt_idx on notify.delivery (provider_receipt_id) where provider_receipt_id is not null and provider_receipt_state is null;

-- 1d — the sparse override + THE MANDATORY GUARD (§3.3: declarative DDL)
create table if not exists notify.preference (
  identity_id    uuid not null references auth.users(id) on delete cascade,
  type_key       text not null,
  channel        text not null check (channel in ('push','email')),
  enabled        boolean not null,
  delivery_class text not null,
  updated_at     timestamptz not null default now(),
  primary key (identity_id, type_key, channel),
  constraint preference_type_class_fk foreign key (type_key, delivery_class)
    references notify.notification_type (type_key, delivery_class) on update cascade on delete restrict,
  constraint preference_not_mandatory_ck check (delivery_class <> 'mandatory')
);

-- 1e — copy, per (key, locale, channel, version) — C18 versioned (§5.2)
create table if not exists notify.template (
  template_key text not null,
  locale       text not null,
  channel      text not null check (channel in ('push','email','in_app')),
  version      integer not null check (version > 0),
  subject      text,
  body         text not null,
  created_at   timestamptz not null default now(),
  primary key (template_key, locale, channel, version)
);

-- 1f — transport facts, never preferences (§3.5)
create table if not exists notify.identity_channel_state (
  identity_id uuid not null references auth.users(id) on delete cascade,
  channel     text not null check (channel in ('push','email')),
  state       text not null check (state in ('ok','bounced','complained','unreachable')),
  since       timestamptz not null default now(),
  reason      text,
  primary key (identity_id, channel)
);

-- 1g — ADDITIVE columns on 076's outbox: the bounded-expansion cursor (§17.24 (i))
alter table notify.outbox add column if not exists expand_cursor uuid;
alter table notify.outbox add column if not exists expanded_count integer not null default 0;

-- 1h — ADDITIVE columns on public.push_tokens (schema §13.4 / O-N11): `revoked_at IS NULL`
--   becomes the authoritative predicate; is_active is left in place and untouched.
alter table public.push_tokens add column if not exists revoked_at timestamptz;
alter table public.push_tokens add column if not exists revoked_reason text;
alter table public.push_tokens add column if not exists provider_receipt_checked_at timestamptz;
alter table public.push_tokens add column if not exists last_provider_error text;
create index if not exists push_tokens_live_idx on public.push_tokens (user_id) where revoked_at is null;

-- ============================================================================
-- PART 2 — RLS + GRANTS (NOTIF §6.2; RLS §16.9; GP-1/GP-2)
-- ============================================================================
alter table notify.notification_type      enable row level security;
alter table notify.notification           enable row level security;
alter table notify.delivery               enable row level security;
alter table notify.preference             enable row level security;
alter table notify.template               enable row level security;
alter table notify.identity_channel_state enable row level security;
revoke all on notify.notification_type, notify.notification, notify.delivery, notify.preference, notify.template, notify.identity_channel_state
  from public, anon, authenticated, service_role;

-- E-152: the client surface lands HERE, so authenticated gains USAGE on notify
-- (076's wall was the state with no client object; RLS §16.9/§11 is the grant
-- authority — an owner-scoped table and nine EXEC: authenticated RPCs are inert
-- without it; the emit pair stays service_role-only; anon stays walled).
grant usage on schema notify to authenticated;

-- notify.notification — the 040 posture verbatim
grant select on notify.notification to authenticated;
grant update (read_at) on notify.notification to authenticated;
drop policy if exists notify_notification_sel_owner on notify.notification;
create policy notify_notification_sel_owner on notify.notification for select to authenticated
  using (recipient_id = auth.uid());
drop policy if exists notify_notification_upd_owner on notify.notification;
create policy notify_notification_upd_owner on notify.notification for update to authenticated
  using (recipient_id = auth.uid()) with check (recipient_id = auth.uid());
-- NO INSERT policy, NO DELETE policy, for any client role.

-- notify.preference — owner-scoped; the mandatory guard is DDL (§3.3), never RLS
grant select, insert, update on notify.preference to authenticated;
drop policy if exists notify_preference_sel_owner on notify.preference;
create policy notify_preference_sel_owner on notify.preference for select to authenticated using (identity_id = auth.uid());
drop policy if exists notify_preference_ins_owner on notify.preference;
create policy notify_preference_ins_owner on notify.preference for insert to authenticated with check (identity_id = auth.uid());
drop policy if exists notify_preference_upd_owner on notify.preference;
create policy notify_preference_upd_owner on notify.preference for update to authenticated using (identity_id = auth.uid()) with check (identity_id = auth.uid());
-- notification_type · template · delivery · identity_channel_state: RLS on, ZERO policies, no client grant.

-- ============================================================================
-- PART 3 — THE REGISTRY SEED: the 31 reduced IN types (ODR-3 §1 + OR-15 + OR-17)
-- Channels transcribed from NOTIF §2.2 ("I" is the row itself, never a
-- delivery; upper-case P/E = default on, lower-case = default off). Every E is
-- conditional on N1 and is born suppressed/channel_unavailable (§2.1).
-- ============================================================================
insert into notify.notification_type
  (type_key, delivery_class, allowed_channels, default_channels, target_kind, template_key, group_label, display_label, description, mandatory_reason)
values
  -- Group A — the transaction record (§3.4)
  ('purchase_confirmed',      'mandatory', '{push,email}', '{push,email}', 'order',       'purchase_confirmed',      'Purchases', 'Purchase confirmed',        'Your payment was received.',                                'transaction_record'),
  ('ticket_ready',            'mandatory', '{push}',       '{push}',       'order',       'ticket_ready',            'Purchases', 'Tickets ready',             'Your tickets are in your account.',                          'transaction_record'),
  ('purchase_failed',         'mandatory', '{push}',       '{push}',       'order',       'purchase_failed',         'Purchases', 'Purchase failed',           'A payment did not go through.',                              'transaction_record'),
  ('wallet_pass_available',   'default_on','{push}',       '{}',           'ticket_pass', 'wallet_pass_available',   'Tickets',   'Wallet pass available',     'An Entry Pass can be added to your wallet.',                 null),
  -- Group B — custody
  ('ownership_changed',       'mandatory', '{push}',       '{push}',       'ticket',      'ownership_changed',       'Tickets',   'Ticket ownership changed',  'A ticket moved into or out of your account.',                'custody_change'),
  -- Group C — payouts
  ('payout_released',         'mandatory', '{push,email}', '{push,email}', 'payout',      'payout_released',         'Payouts',   'Payout sent',               'A payout has been sent to your destination.',                'money_movement'),
  ('payout_failed',           'mandatory', '{push,email}', '{push,email}', 'payout',      'payout_failed',           'Payouts',   'Payout failed',             'A payout could not be completed.',                           'money_movement'),
  ('payout_on_hold',          'mandatory', '{push}',       '{push}',       'payout',      'payout_on_hold',          'Payouts',   'Payout on hold',            'A payout is being held.',                                    'money_movement'),
  ('staff_payout_failed',     'mandatory', '{push,email}', '{push,email}', 'payout',      'staff_payout_failed',     'Payouts',   'Organization payout failed','An organization payout could not be completed.',             'money_movement'),
  ('payout_request_pending_approval','mandatory','{push}', '{push}',       'payout',      'payout_request_pending_approval','Payouts','Payout awaiting approval','A payout request is waiting for an approver.',           'money_movement'),
  -- Group F — refunds
  ('refund_requested',        'mandatory', '{push,email}', '{push,email}', 'refund',      'refund_requested',        'Refunds',   'Refund requested',          'A refund has been requested for your order.',                'money_movement'),
  ('refund_submitted',        'mandatory', '{push,email}', '{email}',      'refund',      'refund_submitted',        'Refunds',   'Refund submitted',          'A refund is on its way back to your payment method.',        'money_movement'),
  ('refund_request_approved', 'mandatory', '{push,email}', '{push,email}', 'refund',      'refund_request_approved', 'Refunds',   'Refund request approved',   'A refund request was approved.',                             'money_movement'),
  ('refund_request_parked',   'mandatory', '{push}',       '{push}',       'refund',      'refund_request_parked',   'Refunds',   'Refund awaiting approval',  'A refund request is waiting for an approver.',               'money_movement'),
  ('refund_request_denied',   'mandatory', '{push,email}', '{push,email}', 'refund',      'refund_request_denied',   'Refunds',   'Refund request denied',     'A refund request was denied.',                               'money_movement'),
  ('refund_request_expired',  'mandatory', '{push}',       '{push}',       'refund',      'refund_request_expired',  'Refunds',   'Refund request expired',    'A refund request expired without a decision.',               'money_movement'),
  ('refund_request_cancelled','mandatory', '{push,email}', '{push,email}', 'refund',      'refund_request_cancelled','Refunds',   'Refund request cancelled',  'A refund request was cancelled.',                            'money_movement'),
  ('refund_completed',        'mandatory', '{push,email}', '{push,email}', 'refund',      'refund_completed',        'Refunds',   'Refund completed',          'A refund has been returned to your payment method.',         'money_movement'),
  ('refund_failed',           'mandatory', '{push,email}', '{push,email}', 'refund',      'refund_failed',           'Refunds',   'Refund failed',             'A refund could not be completed.',                           'money_movement'),
  -- Group E — entitlement viability
  ('event_cancelled',         'mandatory', '{push,email}', '{push,email}', 'event_session','event_cancelled',        'Events',    'Event cancelled',           'An event you hold tickets for was cancelled.',               'entitlement_viability'),
  ('event_time_changed',      'mandatory', '{push,email}', '{push,email}', 'event_session','event_time_changed',     'Events',    'Event time changed',        'The time of an event you hold tickets for changed.',         'entitlement_viability'),
  ('event_venue_changed',     'mandatory', '{push,email}', '{push,email}', 'event_session','event_venue_changed',    'Events',    'Event venue changed',       'The venue of an event you hold tickets for changed.',        'entitlement_viability'),
  ('event_postponed',         'mandatory', '{push,email}', '{push,email}', 'event_session','event_postponed',        'Events',    'Event postponed',           'An event you hold tickets for was postponed.',               'entitlement_viability'),
  -- Group G — account security
  ('security_password_changed',           'mandatory', '{push,email}', '{push,email}', 'account_security', 'security_password_changed',           'Security', 'Password changed',          'Your password was changed.',                     'account_security'),
  ('security_payout_destination_changed', 'mandatory', '{push,email}', '{push,email}', 'account_security', 'security_payout_destination_changed', 'Security', 'Payout destination changed','A payout destination was changed.',              'account_security'),
  ('security_payout_method_added',        'mandatory', '{push,email}', '{push,email}', 'account_security', 'security_payout_method_added',        'Security', 'Payout method added',       'A new payout destination was added.',            'account_security'),
  ('security_org_role_granted',           'mandatory', '{push,email}', '{push,email}', 'account_security', 'security_org_role_granted',           'Security', 'Role granted',              'A role was granted in an organization.',         'account_security'),
  ('security_org_role_revoked',           'mandatory', '{push,email}', '{push,email}', 'account_security', 'security_org_role_revoked',           'Security', 'Role revoked',              'A role was revoked in an organization.',         'account_security'),
  -- Group D — promoter (ON; IN by the explicit OR-5 clause)
  ('promoter_commission_accrued','default_on','{push,email}','{email}',    'payout',      'promoter_commission_accrued','Promoter','Commission recorded',      'A commission was recorded on a sale you referred.',          null),
  -- Group H' — the OR-13 deletion lifecycle pair (OR-17)
  ('account_deletion_pending',   'mandatory', '{push,email}', '{push,email}', 'account_security', 'account_deletion_pending',   'Account', 'Account deletion requested', 'Your account deletion request was received.',  'account_security'),
  ('account_deletion_completed', 'mandatory', '{email}',      '{email}',      'account_security', 'account_deletion_completed', 'Account', 'Account deletion completed', 'Your account deletion was completed.',        'account_security')
on conflict (type_key) do nothing;

-- ============================================================================
-- PART 4 — TEMPLATES: en-US v1, channels in_app + push. NO email rows (N1).
-- Placeholders are {{param}}; `{{amount}}` is derived from amount_minor +
-- currency at render time (§5.4: money travels raw). §5.5/§8.4: push copy for
-- money and custody types carries NO amount and NO counterparty name; no
-- forbidden vocabulary anywhere (asserted N-A18).
-- ============================================================================
insert into notify.template (template_key, locale, channel, version, subject, body) values
  ('purchase_confirmed','en-US','in_app',1,'Purchase confirmed','Your payment of {{amount}} for {{event_title}} was received.'),
  ('purchase_confirmed','en-US','push',  1,'Purchase confirmed','Your payment for {{event_title}} was received.'),
  ('ticket_ready','en-US','in_app',1,'Tickets ready','Your tickets for {{event_title}} are in your account.'),
  ('ticket_ready','en-US','push',  1,'Tickets ready','Your tickets for {{event_title}} are ready.'),
  ('purchase_failed','en-US','in_app',1,'Purchase failed','Your payment did not go through. {{retry_note}}'),
  ('purchase_failed','en-US','push',  1,'Purchase failed','Your payment did not go through.'),
  ('wallet_pass_available','en-US','in_app',1,'Wallet pass available','Your Entry Pass for {{event_title}} can be added to your wallet.'),
  ('wallet_pass_available','en-US','push',  1,'Wallet pass available','Your Entry Pass for {{event_title}} is ready for your wallet.'),
  ('ownership_changed','en-US','in_app',1,'Ticket ownership changed','{{cause_label}}: {{event_title}}.'),
  ('ownership_changed','en-US','push',  1,'Ticket ownership changed','{{cause_label}}. Open the app for details.'),
  ('payout_released','en-US','in_app',1,'Payout sent','A payout of {{amount}} was sent to your destination.'),
  ('payout_released','en-US','push',  1,'Payout sent','A payout was sent to your destination.'),
  ('payout_failed','en-US','in_app',1,'Payout failed','A payout of {{amount}} could not be completed. {{action_required}}'),
  ('payout_failed','en-US','push',  1,'Payout failed','A payout could not be completed. Open the app for details.'),
  ('payout_on_hold','en-US','in_app',1,'Payout on hold','A payout of {{amount}} is being held ({{reason_label}}). No money has moved.'),
  ('payout_on_hold','en-US','push',  1,'Payout on hold','A payout is being held. Open the app for details.'),
  ('staff_payout_failed','en-US','in_app',1,'Organization payout failed','An organization payout of {{amount}} could not be completed. {{action_required}}'),
  ('staff_payout_failed','en-US','push',  1,'Organization payout failed','An organization payout could not be completed.'),
  ('payout_request_pending_approval','en-US','in_app',1,'Payout awaiting approval','A payout request of {{amount}} for {{org_name}} is waiting for an approver.'),
  ('payout_request_pending_approval','en-US','push',  1,'Payout awaiting approval','A payout request is waiting for your approval.'),
  ('refund_requested','en-US','in_app',1,'Refund requested','A refund of {{amount}} was requested for your order ({{reason_label}}).'),
  ('refund_requested','en-US','push',  1,'Refund requested','A refund was requested for your order.'),
  ('refund_submitted','en-US','in_app',1,'Refund submitted','A refund of {{amount}} is on its way back to your payment method.'),
  ('refund_submitted','en-US','push',  1,'Refund submitted','A refund is on its way back to your payment method.'),
  ('refund_request_approved','en-US','in_app',1,'Refund request approved','A refund request of {{amount}} was approved.'),
  ('refund_request_approved','en-US','push',  1,'Refund request approved','A refund request was approved.'),
  ('refund_request_parked','en-US','in_app',1,'Refund awaiting approval','A refund request for {{org_name}} is waiting for an approver.'),
  ('refund_request_parked','en-US','push',  1,'Refund awaiting approval','A refund request is waiting for your approval.'),
  ('refund_request_denied','en-US','in_app',1,'Refund request denied','A refund request was denied ({{reason_label}}).'),
  ('refund_request_denied','en-US','push',  1,'Refund request denied','A refund request was denied.'),
  ('refund_request_expired','en-US','in_app',1,'Refund request expired','A refund request expired without a decision. No money has moved.'),
  ('refund_request_expired','en-US','push',  1,'Refund request expired','A refund request expired without a decision.'),
  ('refund_request_cancelled','en-US','in_app',1,'Refund request cancelled','A refund request was cancelled ({{reason_label}}). No money has moved.'),
  ('refund_request_cancelled','en-US','push',  1,'Refund request cancelled','A refund request was cancelled.'),
  ('refund_completed','en-US','in_app',1,'Refund completed','A refund of {{amount}} was returned to your payment method.'),
  ('refund_completed','en-US','push',  1,'Refund completed','A refund was returned to your payment method.'),
  ('refund_failed','en-US','in_app',1,'Refund failed','A refund of {{amount}} could not be completed. {{next_step}}'),
  ('refund_failed','en-US','push',  1,'Refund failed','A refund could not be completed. Open the app for details.'),
  ('event_cancelled','en-US','in_app',1,'Event cancelled','{{event_title}} was cancelled. {{refund_note}}'),
  ('event_cancelled','en-US','push',  1,'Event cancelled','{{event_title}} was cancelled. Open the app for details.'),
  ('event_time_changed','en-US','in_app',1,'Event time changed','The time of {{event_title}} changed. Check the new time in the app.'),
  ('event_time_changed','en-US','push',  1,'Event time changed','The time of {{event_title}} changed.'),
  ('event_venue_changed','en-US','in_app',1,'Event venue changed','The venue of {{event_title}} changed to {{new_venue_name}}.'),
  ('event_venue_changed','en-US','push',  1,'Event venue changed','The venue of {{event_title}} changed.'),
  ('event_postponed','en-US','in_app',1,'Event postponed','{{event_title}} was postponed. Your tickets remain valid for the new date.'),
  ('event_postponed','en-US','push',  1,'Event postponed','{{event_title}} was postponed.'),
  ('security_password_changed','en-US','in_app',1,'Password changed','Your password was changed. If this was not you, secure your account now.'),
  ('security_password_changed','en-US','push',  1,'Password changed','Your password was changed. If this was not you, secure your account now.'),
  ('security_payout_destination_changed','en-US','in_app',1,'Payout destination changed','A payout destination ending in {{destination_last4}} was set.'),
  ('security_payout_destination_changed','en-US','push',  1,'Payout destination changed','A payout destination was changed. If this was not you, contact support.'),
  ('security_payout_method_added','en-US','in_app',1,'Payout method added','A payout destination ending in {{method_last4}} was added.'),
  ('security_payout_method_added','en-US','push',  1,'Payout method added','A payout destination was added. If this was not you, contact support.'),
  ('security_org_role_granted','en-US','in_app',1,'Role granted','The {{role_label}} role was granted to {{subject_label}} in {{org_name}}.'),
  ('security_org_role_granted','en-US','push',  1,'Role granted','A {{role_label}} role was granted in {{org_name}}.'),
  ('security_org_role_revoked','en-US','in_app',1,'Role revoked','The {{role_label}} role was revoked from {{subject_label}} in {{org_name}}.'),
  ('security_org_role_revoked','en-US','push',  1,'Role revoked','A {{role_label}} role was revoked in {{org_name}}.'),
  ('promoter_commission_accrued','en-US','in_app',1,'Commission recorded','A commission of {{amount}} was recorded on a sale you referred. It is being held until funding is confirmed.'),
  ('promoter_commission_accrued','en-US','push',  1,'Commission recorded','A commission was recorded on a sale you referred.'),
  ('account_deletion_pending','en-US','in_app',1,'Account deletion requested','Your account deletion request was received. You can withdraw it from Settings while it is pending.'),
  ('account_deletion_pending','en-US','push',  1,'Account deletion requested','Your account deletion request was received.'),
  ('account_deletion_completed','en-US','in_app',1,'Account deletion completed','Your account deletion was completed. This account can no longer be used to sign in.')
on conflict (template_key, locale, channel, version) do nothing;

-- ============================================================================
-- PART 5 — FUNCTIONS (RPC §17.24/§17.25; NOTIF §6.3; RLS §11)
-- All SECURITY DEFINER, search_path = '', owned by postgres, REVOKE-then-GRANT
-- (067 discipline). Internal six → service_role only. Consumer nine →
-- authenticated, auth.uid()-scoped, fail-closed on a NULL uid.
-- ============================================================================

-- 5.1 resolve_web_link — the closed target set → a client route (§4.4: never a
-- URL in a payload; the mapping composes onto routes that exist in web/ today
-- (E-156) — a hub page where no detail route exists yet).
create or replace function notify.resolve_web_link(p_target_kind text, p_target_id uuid)
returns text language plpgsql stable security definer set search_path = ''
as $$
begin
  return case p_target_kind
    when 'ticket'                    then '/account/purchases'
    when 'ticket_pass'               then '/account/purchases'
    when 'event'                     then '/browse'
    when 'event_session'             then '/browse'
    when 'listing'                   then '/listing/' || p_target_id::text
    when 'listing_native'            then '/listing/' || p_target_id::text
    when 'p2p_transfer_in'           then '/transfer/receive'
    when 'p2p_transfer_out'          then '/transfer/send'
    when 'external_transfer_send'    then '/transfer/send'
    when 'external_transfer_receive' then '/transfer/receive'
    when 'order'                     then '/account/purchases'
    when 'refund'                    then '/account/purchases'
    when 'payout'                    then '/account/sales'
    when 'account_security'          then '/account/settings'
    when 'account_notifications'     then '/account/notifications'
    when 'announcement'              then '/account/notifications'
    when 'none'                      then '/account/notifications'
    else null
  end;
end $$;

-- 5.2 channel_enabled — registry → mandatory → sparse override → default (§3.2;
-- §17.24 order of evaluation). A transport fact (§3.5) is NOT consulted here.
create or replace function notify.channel_enabled(p_identity uuid, p_type_key text, p_channel text)
returns boolean language plpgsql stable security definer set search_path = ''
as $$
declare
  v_class text; v_allowed text[]; v_default text[]; v_active boolean; v_override boolean;
begin
  select t.delivery_class, t.allowed_channels, t.default_channels, t.active
    into v_class, v_allowed, v_default, v_active
    from notify.notification_type t where t.type_key = p_type_key;
  if v_class is null or not v_active then return false; end if;
  if not (p_channel = any (v_allowed)) then return false; end if;
  if v_class = 'mandatory' then return true; end if;
  select p.enabled into v_override
    from notify.preference p
   where p.identity_id = p_identity and p.type_key = p_type_key and p.channel = p_channel;
  if found then return v_override; end if;
  return p_channel = any (v_default);
end $$;

-- 5.3 enqueue — hop 3. NON-RAISING (057:80-86 shape): a notification failure
-- never fails the caller. Idempotent on dedupe_key (hop-3 key) and on
-- (notification_id, channel) (hop-4 key). Every E row is born suppressed /
-- channel_unavailable until N1. Push for an ERASED identity is suppressed
-- (identity_erased); a non-ok transport fact suppresses push as no_transport,
-- recorded undelivered_mandatory for the mandatory class (§3.5).
create or replace function notify.enqueue(
  p_recipient uuid, p_type_key text, p_subject_kind text, p_subject_id uuid,
  p_params jsonb default '{}'::jsonb, p_dedupe_key text default null)
returns uuid language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_id uuid; v_class text; v_allowed text[]; v_target_kind text; v_template text; v_active boolean;
  v_locale text; v_target_id uuid; v_params jsonb; v_ch text; v_state text; v_reason text;
  v_erased boolean; v_chan_state text;
begin
  select t.delivery_class, t.allowed_channels, t.target_kind, t.template_key, t.active
    into v_class, v_allowed, v_target_kind, v_template, v_active
    from notify.notification_type t where t.type_key = p_type_key;
  if v_class is null or not v_active or p_recipient is null then return null; end if;

  v_params := coalesce(p_params, '{}'::jsonb);
  v_target_id := case
    when v_target_kind in ('account_security','account_notifications','none') then null
    when v_params ? 'target_id' and (v_params->>'target_id') ~ '^[0-9a-f-]{36}$' then (v_params->>'target_id')::uuid
    else p_subject_id end;
  v_params := v_params - 'target_id';

  -- §5.4 chain: stated preference → (device locale: no column, E-157) → 'en-US'
  select coalesce(e.locale, 'en-US'), e.deletion_state = 'ERASED'
    into v_locale, v_erased
    from kernel.identity_ext e where e.identity_id = p_recipient;
  v_locale := coalesce(v_locale, 'en-US');
  v_erased := coalesce(v_erased, false);

  insert into notify.notification
    (recipient_id, type_key, template_key, params, dedupe_key, subject_kind, subject_id, target_kind, target_id, locale_resolved)
  values (p_recipient, p_type_key, v_template, v_params, p_dedupe_key, p_subject_kind, p_subject_id, v_target_kind, v_target_id, v_locale)
  on conflict (dedupe_key) where dedupe_key is not null do nothing
  returning notification_id into v_id;
  if v_id is null then
    -- hop-3 replay: the logical notification already exists; nothing new is written
    select n.notification_id into v_id from notify.notification n where n.dedupe_key = p_dedupe_key;
    return v_id;
  end if;

  foreach v_ch in array v_allowed loop
    v_reason := null;
    if not notify.channel_enabled(p_recipient, p_type_key, v_ch) then
      v_state := 'suppressed'; v_reason := 'preference_off';
    elsif v_ch = 'email' then
      v_state := 'suppressed'; v_reason := 'channel_unavailable';            -- N1 (NOTIF §2.1)
    elsif v_erased then
      v_state := 'suppressed'; v_reason := 'identity_erased';
    else
      select s.state into v_chan_state from notify.identity_channel_state s
       where s.identity_id = p_recipient and s.channel = v_ch;
      if v_chan_state is not null and v_chan_state <> 'ok' then
        v_state := 'suppressed';
        v_reason := case when v_class = 'mandatory' then 'undelivered_mandatory' else 'no_transport' end;
      else
        v_state := 'pending';
      end if;
    end if;
    insert into notify.delivery (notification_id, channel, state, suppress_reason)
    values (v_id, v_ch, v_state, v_reason)
    on conflict (notification_id, channel) do nothing;
  end loop;
  return v_id;
exception when others then
  -- never raise into a producer or the drainer; the row simply is not written
  return null;
end $$;

-- 5.4 drain_outbox — hop 2 → hop 3. One drainer at a time (xact advisory lock);
-- pending envelopes in (occurred_at, sequence) order, FOR UPDATE SKIP LOCKED;
-- each envelope in its own subtransaction: a malformed one is quarantined
-- `dead` with last_error (poison), a transient failure (classes 40/55/57)
-- re-runs up to five times, and one bad row never blocks the batch.
-- Custody expansion (event_cancelled) is CURSOR-BOUNDED (§17.24 (i)): at most
-- 500 tickets per tick, the cursor persisted on the envelope, done only when
-- exhausted. Recipient derivation uses the four §2.4 forms and nothing else.
-- Envelopes of event types with no notification consumer (attribution_recorded,
-- DoorManifest*, anything unmapped) are marked done with zero rows (E-159).
create or replace function notify.drain_outbox(p_limit integer default 200)
returns jsonb language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_lim integer := least(greatest(coalesce(p_limit, 200), 1), 1000);
  r record;
  v_done integer := 0; v_dead integer := 0; v_deferred integer := 0; v_unmapped integer := 0; v_notifs integer := 0;
  v_err text; v_sqlstate text; v_next_state text; v_cursor uuid; v_expanded integer; v_made integer;
  -- scalars (never an unassigned record — 090 lesson)
  v_recipient uuid; v_recipient2 uuid; v_title text; v_amount integer; v_currency text; v_org uuid; v_org_name text;
  v_seq integer; v_from uuid; v_to uuid; v_cause text; v_label text; v_payee_kind text; v_reason text;
  v_session uuid; v_ticket uuid; v_owner uuid; v_n integer; v_id uuid; v_status text; v_role text;
begin
  if not pg_try_advisory_xact_lock(hashtext('notify.drain_outbox')) then
    return jsonb_build_object('skipped', true, 'reason', 'drainer_busy');
  end if;

  for r in
    select o.outbox_id, o.event_type, o.aggregate_kind, o.aggregate_id, o.event_key, o.payload, o.attempt,
           o.expand_cursor, o.expanded_count
      from notify.outbox o
     where o.state = 'pending' and o.occurred_at <= now()
     order by o.occurred_at, o.sequence
     limit v_lim
     for update skip locked
  loop
    v_next_state := 'done'; v_err := null; v_cursor := r.expand_cursor; v_expanded := coalesce(r.expanded_count, 0); v_made := 0;
    begin
      case r.event_type
      -- ---------------------------------------------------------------- A
      when 'purchase_confirmed' then
        -- 088 producer: aggregate market_sale (row-column recipient: buyer_id)
        select s.buyer_id, s.price_minor, s.currency, ev.title
          into v_recipient, v_amount, v_currency, v_title
          from market.market_sale s
          join kernel.tickets t on t.ticket_atom_id = s.ticket_atom_id
          join catalog.event_session es on es.session_id = t.event_session_id
          join catalog.event ev on ev.event_id = es.event_id
         where s.sale_id = r.aggregate_id;
        if v_recipient is null then raise exception 'unresolvable aggregate market_sale %', r.aggregate_id; end if;
        v_id := notify.enqueue(v_recipient, 'purchase_confirmed', 'market_sale', r.aggregate_id,
                  jsonb_build_object('event_title', v_title, 'amount_minor', v_amount, 'currency', v_currency, 'qty', 1),
                  r.event_key);
        v_made := v_made + (v_id is not null)::int;
      -- ---------------------------------------------------------------- B
      when 'ownership_changed' then
        -- 088 producer: aggregate ticket_atom; the log row is (atom, credential_version_after)
        select l.sequence, l.from_identity, l.to_identity, l.cause
          into v_seq, v_from, v_to, v_cause
          from kernel.ticket_ownership_log l
         where l.ticket_atom_id = r.aggregate_id
           and l.credential_version_after = coalesce((r.payload->>'credential_version')::int, -1)
         order by l.sequence desc limit 1;
        if v_seq is null then
          select l.sequence, l.from_identity, l.to_identity, l.cause
            into v_seq, v_from, v_to, v_cause
            from kernel.ticket_ownership_log l
           where l.ticket_atom_id = r.aggregate_id and l.to_identity = (r.payload->>'to_identity')::uuid
           order by l.sequence desc limit 1;
        end if;
        if v_seq is null then raise exception 'unresolvable ownership log for atom %', r.aggregate_id; end if;
        select ev.title into v_title from kernel.tickets t
          join catalog.event_session es on es.session_id = t.event_session_id
          join catalog.event ev on ev.event_id = es.event_id where t.ticket_atom_id = r.aggregate_id;
        -- the plain-verb labels (§5.5: never a cause-code)
        v_label := case v_cause
          when 'p2p_transfer' then 'Transferred to you' when 'market_sale' then 'Bought on the marketplace'
          when 'auction_sale' then 'Won at auction' when 'issue' then 'Issued to you' when 'primary_sale' then 'Issued to you'
          when 'comp' then 'Issued to you' when 'door_sale' then 'Issued to you' when 'import' then 'Added to your account'
          when 'admin_action' then 'Updated by support' when 'refund_void' then 'Returned for refund'
          when 'chargeback' then 'Reversed' else 'Updated' end;
        if v_to is not null then
          v_id := notify.enqueue(v_to, 'ownership_changed', 'ticket_atom', r.aggregate_id,
                    jsonb_build_object('event_title', v_title, 'direction', 'acquired', 'cause_label', v_label),
                    'ownership_changed:' || r.aggregate_id::text || ':' || v_seq::text || ':acquired');
          v_made := v_made + (v_id is not null)::int;
        end if;
        if v_from is not null and v_from is distinct from v_to then
          v_label := case v_cause
            when 'p2p_transfer' then 'Transferred from your account' when 'market_sale' then 'Sold on the marketplace'
            when 'auction_sale' then 'Sold at auction' when 'admin_action' then 'Updated by support'
            when 'refund_void' then 'Returned for refund' when 'chargeback' then 'Reversed' else 'Released from your account' end;
          v_id := notify.enqueue(v_from, 'ownership_changed', 'ticket_atom', r.aggregate_id,
                    jsonb_build_object('event_title', v_title, 'direction', 'released', 'cause_label', v_label),
                    'ownership_changed:' || r.aggregate_id::text || ':' || v_seq::text || ':released');
          v_made := v_made + (v_id is not null)::int;
        end if;
      -- ---------------------------------------------------------------- E (custody expansion, cursor-bounded)
      when 'event_cancelled' then
        select ev.title into v_title from catalog.event ev where ev.event_id = r.aggregate_id;
        if v_title is null then raise exception 'unresolvable aggregate event %', r.aggregate_id; end if;
        v_n := 0;
        -- "the holder of each atom voided by the cascade" (§2.2): the cascade's
        -- refund_void moves custody to SN-VOID (085 §C107, 0000…00f0), so the
        -- holder is the FROM side of that ledger entry; an atom voided without
        -- one falls back to its head. SN-VOID itself is never a recipient.
        for v_ticket, v_session, v_owner in
          select t.ticket_atom_id, t.event_session_id,
                 coalesce(lv.from_identity, t.current_owner_id)
            from kernel.tickets t
            join catalog.event_session es on es.session_id = t.event_session_id
            left join lateral (
              select l.from_identity from kernel.ticket_ownership_log l
               where l.ticket_atom_id = t.ticket_atom_id and l.cause = 'refund_void'
               order by l.sequence desc limit 1) lv on true
           where es.event_id = r.aggregate_id
             and t.state = 'voided'
             and coalesce(lv.from_identity, t.current_owner_id) is not null
             and coalesce(lv.from_identity, t.current_owner_id) <> '00000000-0000-0000-0000-0000000000f0'::uuid
             and (v_cursor is null or t.ticket_atom_id > v_cursor)
           order by t.ticket_atom_id
           limit 500
        loop
          v_id := notify.enqueue(v_owner, 'event_cancelled', 'event_session', v_session,
                    jsonb_build_object('event_title', v_title, 'target_id', v_session,
                      'refund_note', 'If you paid for this ticket, a refund will be requested automatically.'),
                    'event_cancelled:' || v_session::text || ':' || v_ticket::text);
          v_made := v_made + (v_id is not null)::int;
          v_n := v_n + 1; v_cursor := v_ticket;
        end loop;
        v_expanded := v_expanded + v_n;
        if v_n = 500 then v_next_state := 'pending'; end if;    -- more may remain: persist the cursor, run again
      -- ---------------------------------------------------------------- F
      when 'refund_requested' then
        -- 088 producer: aggregate refund; the payer is public.payments.buyer_id
        select p.buyer_id, rf.amount_minor, rf.currency, rf.reason_code
          into v_recipient, v_amount, v_currency, v_cause
          from kernel.refund rf join public.payments p on p.id = rf.payment_id
         where rf.refund_id = r.aggregate_id;
        if v_recipient is null then raise exception 'unresolvable aggregate refund %', r.aggregate_id; end if;
        v_label := case v_cause when 'event_cancelled' then 'event cancelled' when 'buyer_request' then 'your request'
                     when 'oversell_correction' then 'seating correction' when 'dispute' then 'dispute'
                     when 'admin_action' then 'support action' else 'compensation' end;
        v_id := notify.enqueue(v_recipient, 'refund_requested', 'refund', r.aggregate_id,
                  jsonb_build_object('amount_minor', v_amount, 'currency', v_currency, 'reason_label', v_label), r.event_key);
        v_made := v_made + (v_id is not null)::int;
      when 'refund_request_expired', 'refund_request_cancelled' then
        -- 085 producers: aggregate approval_request; payer = venue.order.buyer_id; approver set = org_owner ∪ org_finance
        select ar.org_id, ar.reason_code, o.buyer_id, ar.amount_minor, o.currency
          into v_org, v_cause, v_recipient, v_amount, v_currency
          from kernel.approval_request ar
          left join venue."order" o on ar.subject_kind = 'order' and o.order_id = ar.subject_id
         where ar.request_id = r.aggregate_id;
        if v_org is null then raise exception 'unresolvable aggregate approval_request %', r.aggregate_id; end if;
        select og.display_name into v_org_name from kernel.organization og where og.org_id = v_org;
        v_label := coalesce(nullif(replace(coalesce(r.payload->>'cause', v_cause, ''), '_', ' '), ''), 'no decision');
        if v_recipient is not null then
          v_id := notify.enqueue(v_recipient, r.event_type, 'approval_request', r.aggregate_id,
                    jsonb_build_object('amount_minor', v_amount, 'currency', v_currency, 'reason_label', v_label, 'org_name', v_org_name),
                    r.event_key || ':' || v_recipient::text);
          v_made := v_made + (v_id is not null)::int;
        end if;
        if r.event_type = 'refund_request_expired' then          -- "both parties"
          for v_recipient2 in
            select m.identity_id from kernel.org_member m
             where m.org_id = v_org and m.role in ('org_owner','org_finance') and m.identity_id is distinct from v_recipient
          loop
            v_id := notify.enqueue(v_recipient2, r.event_type, 'approval_request', r.aggregate_id,
                      jsonb_build_object('amount_minor', v_amount, 'currency', v_currency, 'reason_label', v_label, 'org_name', v_org_name),
                      r.event_key || ':' || v_recipient2::text);
            v_made := v_made + (v_id is not null)::int;
          end loop;
        end if;
      -- ---------------------------------------------------------------- C
      when 'payout_request_pending_approval' then
        -- 087 producer: aggregate settlement; the org approver set (form 3)
        select st.org_id, st.currency into v_org, v_currency from venue.settlement st where st.settlement_id = r.aggregate_id;
        v_org := coalesce(v_org, (r.payload->>'org_id')::uuid);
        if v_org is null then raise exception 'unresolvable aggregate settlement %', r.aggregate_id; end if;
        select og.display_name into v_org_name from kernel.organization og where og.org_id = v_org;
        v_amount := (r.payload->>'amount_minor')::int;
        for v_recipient in
          select m.identity_id from kernel.org_member m where m.org_id = v_org and m.role in ('org_owner','org_finance')
        loop
          v_id := notify.enqueue(v_recipient, 'payout_request_pending_approval', 'settlement', r.aggregate_id,
                    jsonb_build_object('amount_minor', v_amount, 'currency', coalesce(v_currency, 'USD'), 'org_name', v_org_name),
                    r.event_key || ':' || v_recipient::text);
          v_made := v_made + (v_id is not null)::int;
        end loop;
      when 'payout_on_hold' then
        -- 088/090 producers: aggregate payout; payee identity, or the payee org's approver set
        select po.payee_kind, po.payee_identity_id, po.payee_org_id, po.amount_minor, po.currency, po.hold_reason_code
          into v_payee_kind, v_recipient, v_org, v_amount, v_currency, v_reason
          from kernel.payout po where po.payout_id = r.aggregate_id;
        if v_payee_kind is null then raise exception 'unresolvable aggregate payout %', r.aggregate_id; end if;
        v_label := case coalesce(r.payload->>'reason', v_reason)
                     when 'dispute' then 'a dispute is open' when 'unfunded_settlement' then 'funding not yet confirmed'
                     else replace(coalesce(r.payload->>'reason', v_reason, 'under review'), '_', ' ') end;
        if v_payee_kind = 'identity' then
          v_id := notify.enqueue(v_recipient, 'payout_on_hold', 'payout', r.aggregate_id,
                    jsonb_build_object('amount_minor', v_amount, 'currency', v_currency, 'reason_label', v_label), r.event_key);
          v_made := v_made + (v_id is not null)::int;
        else
          for v_recipient in
            select m.identity_id from kernel.org_member m where m.org_id = v_org and m.role in ('org_owner','org_finance')
          loop
            v_id := notify.enqueue(v_recipient, 'payout_on_hold', 'payout', r.aggregate_id,
                      jsonb_build_object('amount_minor', v_amount, 'currency', v_currency, 'reason_label', v_label),
                      r.event_key || ':' || v_recipient::text);
            v_made := v_made + (v_id is not null)::int;
          end loop;
        end if;
      -- ---------------------------------------------------------------- D
      when 'promoter_commission_accrued' then
        -- 090 producer: aggregate attribution; payload promoter_id → venue.promoter.identity_id
        select pr.identity_id, pr.currency into v_recipient, v_currency
          from venue.promoter pr where pr.promoter_id = (r.payload->>'promoter_id')::uuid;
        if v_recipient is null then raise exception 'unresolvable promoter for attribution %', r.aggregate_id; end if;
        v_id := notify.enqueue(v_recipient, 'promoter_commission_accrued', 'attribution', r.aggregate_id,
                  jsonb_build_object('amount_minor', (r.payload->>'amount_minor')::int, 'currency', coalesce(v_currency, 'USD'),
                                     'target_id', (r.payload->>'payout_id')),
                  r.event_key);
        v_made := v_made + (v_id is not null)::int;
      -- ---------------------------------------------------------------- H' (OR-13 lifecycle; self, form 4)
      when 'account_deletion_pending', 'account_deletion_completed' then
        v_id := notify.enqueue(r.aggregate_id, r.event_type, 'identity', r.aggregate_id,
                  jsonb_build_object('deletion_requested_at', r.payload->>'deletion_requested_at'), r.event_key);
        v_made := v_made + (v_id is not null)::int;
      -- ---------------------------------------------------------------- G (subject ∪ org_owner)
      when 'security_org_role_granted', 'security_org_role_revoked' then
        v_org := (r.payload->>'org_id')::uuid;
        if v_org is null then raise exception 'security role envelope without org_id'; end if;
        select og.display_name into v_org_name from kernel.organization og where og.org_id = v_org;
        v_role := replace(coalesce(r.payload->>'role_label', 'member'), '_', ' ');
        v_id := notify.enqueue(r.aggregate_id, r.event_type, 'identity', r.aggregate_id,
                  jsonb_build_object('role_label', v_role, 'org_name', v_org_name, 'subject_label', 'you'),
                  r.event_key || ':' || r.aggregate_id::text);
        v_made := v_made + (v_id is not null)::int;
        select coalesce(pf.display_name, 'a member') into v_label from public.profiles pf where pf.id = r.aggregate_id;
        for v_recipient in
          select m.identity_id from kernel.org_member m
           where m.org_id = v_org and m.role = 'org_owner' and m.identity_id <> r.aggregate_id
        loop
          v_id := notify.enqueue(v_recipient, r.event_type, 'identity', r.aggregate_id,
                    jsonb_build_object('role_label', v_role, 'org_name', v_org_name, 'subject_label', coalesce(v_label, 'a member')),
                    r.event_key || ':' || v_recipient::text);
          v_made := v_made + (v_id is not null)::int;
        end loop;
      else
        v_unmapped := v_unmapped + 1;     -- a fact with no notification consumer (E-159)
      end case;
    exception when others then
      get stacked diagnostics v_err = message_text, v_sqlstate = returned_sqlstate;
      if left(v_sqlstate, 2) in ('40','55','57') and r.attempt < 5 then
        v_next_state := 'pending'; v_deferred := v_deferred + 1;
      else
        v_next_state := 'dead'; v_dead := v_dead + 1;
      end if;
    end;

    update notify.outbox o
       set state = v_next_state,
           attempt = o.attempt + 1,
           last_error = case when v_err is null then o.last_error else left(v_err, 500) end,
           expand_cursor = case when v_next_state = 'pending' and v_err is null then v_cursor else o.expand_cursor end,
           expanded_count = v_expanded,
           claimed_until = null
     where o.outbox_id = r.outbox_id;
    v_notifs := v_notifs + v_made;
    if v_next_state = 'done' then v_done := v_done + 1;
    elsif v_next_state = 'pending' and v_err is null then v_deferred := v_deferred + 1; end if;
  end loop;

  -- 'resolved' = enqueue calls that resolved to a logical notification (new OR a hop-3 replay of an existing one)
  return jsonb_build_object('done', v_done, 'dead', v_dead, 'deferred', v_deferred, 'unmapped', v_unmapped, 'resolved', v_notifs);
end $$;

-- 5.5 claim_deliveries — hop 4 (§17.25). ONE `UPDATE … SKIP LOCKED … RETURNING`
-- under a lease read from config; the lease is OWNER-UNSET (PFA-22 shape) so
-- the claim FAILS CLOSED until the owner sets notify.delivery_lease_interval.
-- Push/email copy is rendered here, at send time, and frozen into
-- notify.delivery.rendered_* (§5.3) — the two rendered columns ride the return
-- (E-155: additive to the nine §17.25 fields so the edge can send without a
-- template read).
create or replace function notify.claim_deliveries(p_channel text, p_limit integer default 200)
returns table (
  delivery_id uuid, notification_id uuid, channel text, attempt integer, recipient_id uuid,
  type_key text, template_key text, params jsonb, locale_resolved text,
  rendered_subject text, rendered_body text)
language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_lease interval; v_raw text; v_lim integer := least(greatest(coalesce(p_limit, 200), 1), 500);
  d record; v_subject text; v_body text; v_m text; v_amount text;
begin
  if p_channel not in ('push','email') then
    raise exception 'precondition_failed: channel must be push or email' using errcode = 'P0001';
  end if;
  select (c.value #>> '{}') into v_raw from catalog.platform_config c
   where c.key = 'notify.delivery_lease_interval' order by c.version desc limit 1;
  if v_raw is null then
    raise exception 'precondition_failed: notify.delivery_lease_interval is unset (owner-set config, PFA-22)' using errcode = 'P0001';
  end if;
  v_lease := v_raw::interval;

  -- a row whose lease keeps expiring with no result (a sender that dies after
  -- every claim) is NOT re-claimable forever: five claims and it is dead-lettered
  -- on the row itself (red-team C, at-least-once has a ceiling)
  update notify.delivery dl
     set state = 'dead', claimed_until = null, last_error = coalesce(dl.last_error, 'lease expired: attempts exhausted')
   where dl.channel = p_channel and dl.state = 'claimed' and dl.claimed_until < now() and dl.attempt >= 5;

  for d in
    with picked as (
      select x.delivery_id
        from notify.delivery x
       where x.channel = p_channel
         and ((x.state = 'pending' and x.next_attempt_at <= now())
           or (x.state = 'claimed' and x.claimed_until < now()))      -- an expired lease is re-claimable (at-least-once)
       order by x.next_attempt_at
       limit v_lim
         for update skip locked
    ), claimed as (
      update notify.delivery dl
         set state = 'claimed', claimed_until = now() + v_lease, attempt = dl.attempt + 1
        from picked
       where dl.delivery_id = picked.delivery_id
       returning dl.delivery_id, dl.notification_id, dl.channel, dl.attempt
    )
    select c.delivery_id, c.notification_id, c.channel, c.attempt,
           n.recipient_id, n.type_key, n.template_key, n.params, n.locale_resolved
      from claimed c join notify.notification n on n.notification_id = c.notification_id
  loop
    v_subject := null; v_body := null;
    select t.subject, t.body into v_subject, v_body from notify.template t
     where t.template_key = d.template_key and t.channel = p_channel and t.locale = d.locale_resolved
     order by t.version desc limit 1;
    if v_body is null then
      select t.subject, t.body into v_subject, v_body from notify.template t
       where t.template_key = d.template_key and t.channel = p_channel and t.locale = 'en-US'
       order by t.version desc limit 1;
    end if;
    if v_body is null then
      -- no copy for this (template, channel): never hand the edge an empty wire
      -- message — the row is dead-lettered with the reason and not returned
      update notify.delivery dl set state = 'dead', claimed_until = null, last_error = 'template_missing:' || d.template_key || ':' || p_channel
       where dl.delivery_id = d.delivery_id;
      continue;
    end if;
    v_amount := case when d.params ? 'amount_minor' and (d.params->>'amount_minor') ~ '^-?[0-9]+$'
                     then to_char((d.params->>'amount_minor')::numeric / 100, 'FM999,999,999,990.00') || ' ' || coalesce(d.params->>'currency', '')
                     else null end;
    for v_m in select m[1] from regexp_matches(coalesce(v_subject, '') || ' ' || coalesce(v_body, ''), '\{\{(\w+)\}\}', 'g') as m loop
      v_subject := replace(coalesce(v_subject, ''), '{{' || v_m || '}}', coalesce(case when v_m = 'amount' then v_amount else d.params->>v_m end, ''));
      v_body    := replace(coalesce(v_body, ''),    '{{' || v_m || '}}', coalesce(case when v_m = 'amount' then v_amount else d.params->>v_m end, ''));
    end loop;
    update notify.delivery dl set rendered_subject = v_subject, rendered_body = v_body where dl.delivery_id = d.delivery_id;
    delivery_id := d.delivery_id; notification_id := d.notification_id; channel := d.channel; attempt := d.attempt;
    recipient_id := d.recipient_id; type_key := d.type_key; template_key := d.template_key; params := d.params;
    locale_resolved := d.locale_resolved; rendered_subject := v_subject; rendered_body := v_body;
    return next;
  end loop;
end $$;

-- 5.6 record_delivery_result — hop 5 (§17.25). Terminal states are guarded
-- no-ops; transient → +1m,+5m,+25m,+2h,+12h, five attempts then dead;
-- device_not_registered → failed + the named token revoked, then the identity
-- becomes push-unreachable iff no live token remains; permanent → dead;
-- no_transport → suppressed (undelivered_mandatory for the mandatory class).
-- p_token is ADDITIVE to the six frozen parameters (E-155): the delivery row is
-- per (notification, channel), so the edge names the device it tried.
create or replace function notify.record_delivery_result(
  p_delivery_id uuid, p_outcome text,
  p_provider_message_id text default null, p_provider_receipt_id text default null,
  p_apns_status text default null, p_error text default null, p_token text default null)
returns jsonb language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_state text; v_attempt integer; v_recipient uuid; v_channel text; v_class text; v_live integer;
  v_backoff interval[] := array['1 minute','5 minutes','25 minutes','2 hours','12 hours']::interval[];
  v_new text; v_next timestamptz;
begin
  if p_outcome not in ('sent','transient','device_not_registered','permanent','no_transport') then
    raise exception 'precondition_failed: unknown outcome %', p_outcome using errcode = 'P0001';
  end if;
  select dl.state, dl.attempt, n.recipient_id, dl.channel, t.delivery_class
    into v_state, v_attempt, v_recipient, v_channel, v_class
    from notify.delivery dl
    join notify.notification n on n.notification_id = dl.notification_id
    join notify.notification_type t on t.type_key = n.type_key
   where dl.delivery_id = p_delivery_id
     for update of dl;
  if v_state is null then
    raise exception 'not_found: delivery %', p_delivery_id using errcode = 'P0002';
  end if;
  if v_state in ('sent','dead','failed','suppressed') then
    return jsonb_build_object('noop', true, 'state', v_state);      -- terminal: guarded no-op
  end if;

  if p_token is not null then
    update public.push_tokens pt
       set last_provider_error = case when p_outcome = 'sent' then null else left(coalesce(p_error, p_outcome), 500) end,
           provider_receipt_checked_at = case when p_provider_receipt_id is not null then now() else pt.provider_receipt_checked_at end
     where pt.token = p_token and pt.user_id = v_recipient;
  end if;

  case p_outcome
  when 'sent' then
    update notify.delivery dl
       set state = 'sent', sent_at = now(), claimed_until = null, last_error = null,
           provider_message_id = coalesce(p_provider_message_id, dl.provider_message_id),
           provider_receipt_id = coalesce(p_provider_receipt_id, dl.provider_receipt_id),
           provider_receipt_state = case when p_provider_receipt_id is not null then 'pending' else dl.provider_receipt_state end
     where dl.delivery_id = p_delivery_id;
    v_new := 'sent';
  when 'transient' then
    if v_attempt >= 5 then
      update notify.delivery dl set state = 'dead', claimed_until = null, last_error = left(coalesce(p_error, 'transient: attempts exhausted'), 500)
       where dl.delivery_id = p_delivery_id;
      v_new := 'dead';
    else
      v_next := now() + v_backoff[greatest(v_attempt, 1)];
      update notify.delivery dl set state = 'pending', claimed_until = null, next_attempt_at = v_next, last_error = left(coalesce(p_error, 'transient'), 500)
       where dl.delivery_id = p_delivery_id;
      v_new := 'pending';
    end if;
  when 'device_not_registered' then
    update notify.delivery dl set state = 'failed', claimed_until = null, last_error = left(coalesce(p_error, 'device_not_registered'), 500)
     where dl.delivery_id = p_delivery_id;
    if p_token is not null then
      update public.push_tokens pt
         set revoked_at = now(), revoked_reason = 'device_not_registered', is_active = false
       where pt.token = p_token and pt.user_id = v_recipient and pt.revoked_at is null;
    end if;
    select count(*) into v_live from public.push_tokens pt where pt.user_id = v_recipient and pt.revoked_at is null;
    if v_live = 0 then
      insert into notify.identity_channel_state (identity_id, channel, state, since, reason)
      values (v_recipient, 'push', 'unreachable', now(), 'device_not_registered')
      on conflict (identity_id, channel) do update
        set state = 'unreachable', since = now(), reason = 'device_not_registered'
        where notify.identity_channel_state.state <> 'unreachable';
    end if;
    v_new := 'failed';
  when 'permanent' then
    update notify.delivery dl set state = 'dead', claimed_until = null, last_error = left(coalesce(p_error, 'permanent'), 500)
     where dl.delivery_id = p_delivery_id;
    v_new := 'dead';
  when 'no_transport' then
    update notify.delivery dl
       set state = 'suppressed', claimed_until = null,
           suppress_reason = case when v_class = 'mandatory' then 'undelivered_mandatory' else 'no_transport' end,
           last_error = left(coalesce(p_error, 'no_transport'), 500)
     where dl.delivery_id = p_delivery_id;
    v_new := 'suppressed';
  end case;
  return jsonb_build_object('noop', false, 'state', v_new, 'attempt', v_attempt);
end $$;

-- ---------------------------------------------------------------------------
-- 5.7 – 5.15 the consumer surface (authenticated; auth.uid()-scoped)
-- ---------------------------------------------------------------------------
-- 5.7 get_inbox — own rows, newest first, KEYSET (never .limit(50)); rendered at
-- read time from template + params + the reader's current locale (§5.3).
create or replace function notify.get_inbox(p_cursor timestamptz default null, p_limit integer default 20)
returns table (
  notification_id uuid, type_key text, group_label text, rendered_title text, rendered_body text,
  target_kind text, target_id uuid, read_at timestamptz, created_at timestamptz)
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid(); v_lim integer := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_locale text; n record; v_subject text; v_body text; v_m text; v_amount text;
begin
  if v_uid is null then return; end if;
  select coalesce(e.locale, 'en-US') into v_locale from kernel.identity_ext e where e.identity_id = v_uid;
  v_locale := coalesce(v_locale, 'en-US');
  for n in
    select x.notification_id, x.type_key, t.group_label, t.display_label, x.template_key, x.params, x.target_kind, x.target_id,
           x.read_at, x.created_at, x.title, x.body
      from notify.notification x
      join notify.notification_type t on t.type_key = x.type_key
     where x.recipient_id = v_uid
       and x.dismissed_at is null
       and (p_cursor is null or x.created_at < p_cursor)
     order by x.created_at desc, x.notification_id desc
     limit v_lim
  loop
    v_subject := null; v_body := null;
    if n.title is not null then                     -- a legacy-shaped row renders its stored copy (N-A21)
      v_subject := n.title; v_body := coalesce(n.body, '');
    else
      select t.subject, t.body into v_subject, v_body from notify.template t
       where t.template_key = n.template_key and t.channel = 'in_app' and t.locale = v_locale
       order by t.version desc limit 1;
      if v_body is null then
        select t.subject, t.body into v_subject, v_body from notify.template t
         where t.template_key = n.template_key and t.channel = 'in_app' and t.locale = 'en-US'
         order by t.version desc limit 1;
      end if;
      v_amount := case when n.params ? 'amount_minor' and (n.params->>'amount_minor') ~ '^-?[0-9]+$'
                       then to_char((n.params->>'amount_minor')::numeric / 100, 'FM999,999,999,990.00') || ' ' || coalesce(n.params->>'currency', '')
                       else null end;
      for v_m in select m[1] from regexp_matches(coalesce(v_subject, '') || ' ' || coalesce(v_body, ''), '\{\{(\w+)\}\}', 'g') as m loop
        v_subject := replace(coalesce(v_subject, ''), '{{' || v_m || '}}', coalesce(case when v_m = 'amount' then v_amount else n.params->>v_m end, ''));
        v_body    := replace(coalesce(v_body, ''),    '{{' || v_m || '}}', coalesce(case when v_m = 'amount' then v_amount else n.params->>v_m end, ''));
      end loop;
    end if;
    notification_id := n.notification_id; type_key := n.type_key; group_label := n.group_label;
    -- a row with no in_app copy still renders its registry label (never a blank card)
    rendered_title := coalesce(nullif(v_subject, ''), n.display_label); rendered_body := coalesce(v_body, '');
    target_kind := n.target_kind; target_id := n.target_id; read_at := n.read_at; created_at := n.created_at;
    return next;
  end loop;
end $$;

-- 5.8 get_unread_count — fails to 0, NEVER raises (it renders in a global header)
create or replace function notify.get_unread_count()
returns integer language plpgsql stable security definer set search_path = ''
as $$
declare v_uid uuid; v_n integer;
begin
  v_uid := auth.uid();
  if v_uid is null then return 0; end if;
  select count(*)::int into v_n from notify.notification x
   where x.recipient_id = v_uid and x.read_at is null and x.dismissed_at is null;
  return coalesce(v_n, 0);
exception when others then
  return 0;
end $$;

-- 5.9 / 5.10 / 5.11 mark_read · mark_all_read · dismiss — writes read_at /
-- dismissed_at only, own rows only; never a delete (GP-2)
create or replace function notify.mark_read(p_ids uuid[])
returns jsonb language plpgsql volatile security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_n integer;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  update notify.notification x set read_at = now()
   where x.recipient_id = v_uid and x.read_at is null and x.notification_id = any (coalesce(p_ids, '{}'::uuid[]));
  get diagnostics v_n = row_count;
  return jsonb_build_object('updated', v_n);
end $$;

create or replace function notify.mark_all_read()
returns jsonb language plpgsql volatile security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_n integer;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  update notify.notification x set read_at = now()
   where x.recipient_id = v_uid and x.read_at is null and x.dismissed_at is null;
  get diagnostics v_n = row_count;
  return jsonb_build_object('updated', v_n);
end $$;

create or replace function notify.dismiss(p_ids uuid[])
returns jsonb language plpgsql volatile security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_n integer;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  update notify.notification x set dismissed_at = now(), read_at = coalesce(x.read_at, now())
   where x.recipient_id = v_uid and x.dismissed_at is null and x.notification_id = any (coalesce(p_ids, '{}'::uuid[]));
  get diagnostics v_n = row_count;
  return jsonb_build_object('updated', v_n);
end $$;

-- 5.12 get_preference_matrix — §3.7: every active, non-legacy type × its allowed
-- channels, with the EFFECTIVE value; mandatory rows render locked, on.
create or replace function notify.get_preference_matrix()
returns table (
  type_key text, group_label text, display_label text, description text, delivery_class text,
  channel text, effective_enabled boolean, mandatory_reason text)
language sql stable security definer set search_path = ''
as $$
  select t.type_key, t.group_label, t.display_label, t.description, t.delivery_class,
         c.channel,
         case when auth.uid() is null then false else notify.channel_enabled(auth.uid(), t.type_key, c.channel) end,
         t.mandatory_reason
    from notify.notification_type t
    cross join lateral unnest(t.allowed_channels) as c(channel)
   where t.active and not t.legacy and auth.uid() is not null
   order by t.group_label, t.display_label, c.channel;
$$;

-- 5.13 set_preference — raises 40003 mandatory_type_not_configurable; the DDL
-- guard (preference_not_mandatory_ck + the composite FK) makes the write
-- impossible regardless (§3.3).
create or replace function notify.set_preference(p_type_key text, p_channel text, p_enabled boolean)
returns jsonb language plpgsql volatile security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_class text; v_allowed text[]; v_active boolean;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  if p_channel not in ('push','email') or p_enabled is null then
    raise exception 'precondition_failed: channel must be push or email and enabled must be set' using errcode = 'P0001';
  end if;
  select t.delivery_class, t.allowed_channels, t.active into v_class, v_allowed, v_active
    from notify.notification_type t where t.type_key = p_type_key;
  if v_class is null or not v_active then
    raise exception 'not_found: notification type %', p_type_key using errcode = 'P0002';
  end if;
  if v_class = 'mandatory' then
    raise exception 'mandatory_type_not_configurable' using errcode = '40003';
  end if;
  if not (p_channel = any (v_allowed)) then
    raise exception 'precondition_failed: channel % is not offered for %', p_channel, p_type_key using errcode = 'P0001';
  end if;
  insert into notify.preference (identity_id, type_key, channel, enabled, delivery_class, updated_at)
  values (v_uid, p_type_key, p_channel, p_enabled, v_class, now())
  on conflict (identity_id, type_key, channel) do update
    set enabled = excluded.enabled, delivery_class = excluded.delivery_class, updated_at = now();
  return jsonb_build_object('type_key', p_type_key, 'channel', p_channel, 'enabled', p_enabled);
end $$;

-- 5.14 register_push_token — upserts on token, ALWAYS sets user_id = auth.uid()
-- (D-4) and last_used = now() (D-5); a re-registration revives a revoked token
-- and clears a push-unreachable fact (§17.24). p_locale is validated and
-- otherwise not persisted (E-157: no device-locale column exists).
create or replace function notify.register_push_token(
  p_token text, p_platform text, p_device_name text default null, p_locale text default null)
returns jsonb language plpgsql volatile security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_id uuid;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  if p_token is null or length(p_token) < 8 or length(p_token) > 4096 then
    raise exception 'precondition_failed: token length' using errcode = 'P0001';
  end if;
  if p_platform not in ('ios','android') then
    raise exception 'precondition_failed: platform must be ios or android' using errcode = 'P0001';
  end if;
  if p_locale is not null and p_locale !~ '^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$' then
    raise exception 'precondition_failed: locale tag' using errcode = 'P0001';
  end if;
  insert into public.push_tokens (user_id, token, platform, device_name, last_used, is_active)
  values (v_uid, p_token, p_platform, left(p_device_name, 120), now(), true)
  on conflict (token) do update
    set user_id = v_uid, platform = excluded.platform, device_name = excluded.device_name,
        last_used = now(), is_active = true,
        revoked_at = null, revoked_reason = null, last_provider_error = null
  returning id into v_id;
  update notify.identity_channel_state s
     set state = 'ok', since = now(), reason = 'token_registered'
   where s.identity_id = v_uid and s.channel = 'push' and s.state = 'unreachable';
  return jsonb_build_object('token_id', v_id, 'platform', p_platform);
end $$;

-- 5.15 revoke_push_token — sets revoked_at on sign-out (D-6); own tokens only,
-- and the count is the only thing a caller learns (no IDOR oracle).
create or replace function notify.revoke_push_token(p_token text)
returns jsonb language plpgsql volatile security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_n integer;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  update public.push_tokens pt
     set revoked_at = now(), revoked_reason = 'signed_out', is_active = false
   where pt.token = p_token and pt.user_id = v_uid and pt.revoked_at is null;
  get diagnostics v_n = row_count;
  return jsonb_build_object('revoked', v_n);
end $$;

-- ============================================================================
-- PART 6 — EXEC POSTURE (RLS §11; 057:90-91 / 067 discipline)
-- ============================================================================
revoke all on function notify.drain_outbox(integer)                                              from public, anon, authenticated;
revoke all on function notify.enqueue(uuid,text,text,uuid,jsonb,text)                            from public, anon, authenticated;
revoke all on function notify.channel_enabled(uuid,text,text)                                    from public, anon, authenticated;
revoke all on function notify.claim_deliveries(text,integer)                                     from public, anon, authenticated;
revoke all on function notify.record_delivery_result(uuid,text,text,text,text,text,text)         from public, anon, authenticated;
revoke all on function notify.resolve_web_link(text,uuid)                                        from public, anon, authenticated;
grant execute on function notify.drain_outbox(integer)                                           to service_role;
grant execute on function notify.enqueue(uuid,text,text,uuid,jsonb,text)                         to service_role;
grant execute on function notify.channel_enabled(uuid,text,text)                                 to service_role;
grant execute on function notify.claim_deliveries(text,integer)                                  to service_role;
grant execute on function notify.record_delivery_result(uuid,text,text,text,text,text,text)      to service_role;
grant execute on function notify.resolve_web_link(text,uuid)                                     to service_role;

revoke all on function notify.get_inbox(timestamptz,integer)                 from public, anon;
revoke all on function notify.get_unread_count()                             from public, anon;
revoke all on function notify.mark_read(uuid[])                              from public, anon;
revoke all on function notify.mark_all_read()                                from public, anon;
revoke all on function notify.dismiss(uuid[])                                from public, anon;
revoke all on function notify.get_preference_matrix()                        from public, anon;
revoke all on function notify.set_preference(text,text,boolean)              from public, anon;
revoke all on function notify.register_push_token(text,text,text,text)       from public, anon;
revoke all on function notify.revoke_push_token(text)                        from public, anon;
grant execute on function notify.get_inbox(timestamptz,integer)              to authenticated;
grant execute on function notify.get_unread_count()                          to authenticated;
grant execute on function notify.mark_read(uuid[])                           to authenticated;
grant execute on function notify.mark_all_read()                             to authenticated;
grant execute on function notify.dismiss(uuid[])                             to authenticated;
grant execute on function notify.get_preference_matrix()                     to authenticated;
grant execute on function notify.set_preference(text,text,boolean)           to authenticated;
grant execute on function notify.register_push_token(text,text,text,text)    to authenticated;
grant execute on function notify.revoke_push_token(text)                     to authenticated;

-- ============================================================================
-- PART 7 — CONFIG + CRON
-- ============================================================================
-- notify.delivery_lease_interval: the key the corpus names (RPC §17.25) with NO
-- frozen value — owner-unset (PFA-22 shape: 078's 'null'::jsonb rows). While
-- unset, claim_deliveries refuses (fail-closed). Restricted visibility.
insert into catalog.platform_config (key, version, value, visibility)
values ('notify.delivery_lease_interval', 1, 'null'::jsonb, 'restricted')
on conflict do nothing;

-- The outbox drainer tick (CRON_SCHEDULE_REGISTER row: 2 min). The two edge
-- ticks (notify-dispatch 1 min, notify-receipts 15 min) need a Vault secret and
-- a dedicated header no frozen byte names — PARKED (E-158), like 087's
-- crm-export precedent required, and RESALE_CHECKOUT_SWEEP_TICK before it.
select cron.schedule('notify-drain-outbox', '*/2 * * * *', $$select notify.drain_outbox(200);$$);

commit;
