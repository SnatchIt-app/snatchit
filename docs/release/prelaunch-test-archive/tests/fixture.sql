-- Synthetic contract fixture only; not a full Supabase/RLS integration proof.
create schema auth; create schema ops; create schema kernel; create schema market;
create role anon; create role authenticated; create role service_role;
create function auth.uid() returns uuid language sql as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create function ops.actor_role() returns text language sql as $$select current_setting('fixture.operator_role',true)$$;
create function ops.assert_role(text[]) returns void language plpgsql as $$begin
 if auth.uid() is null or not(coalesce(ops.actor_role(),'')=any($1))
 or current_setting('fixture.aal',true) is distinct from 'aal2' then
 raise exception 'insufficient_privilege: platform admin and MFA required' using errcode='42501'; end if;
end$$;
create function ops.raise_append_only() returns trigger language plpgsql as $$begin raise exception 'append_only';end$$;
create table public.payments(id uuid primary key,listing_id uuid,buyer_id uuid,seller_id uuid,amount int,buyer_fee int,seller_fee int,total int,mode text,status text,created_at timestamptz,paid_at timestamptz,stripe_payment_intent_id text);
create table public.transfers(id uuid primary key,payment_id uuid references public.payments(id),status text,payout_released_at timestamptz,stripe_transfer_id text);
create table ops."case"(id uuid primary key,subject_kind text,subject_id uuid,status text);
create table ops.case_event(id uuid primary key,case_id uuid references ops."case"(id) on delete cascade);
create table ops.case_note(id uuid primary key,case_id uuid references ops."case"(id) on delete cascade);
create trigger tg_case_event_append_only before delete or update on ops.case_event for each row execute function ops.raise_append_only();
create trigger tg_case_note_append_only before delete or update on ops.case_note for each row execute function ops.raise_append_only();
create table ops.action(id uuid primary key,subject_kind text,subject_id uuid);
create table ops.audit(id uuid primary key default gen_random_uuid(),actor uuid,actor_role text,action text,subject_kind text,subject_id uuid,reason text,after jsonb);
create trigger tg_audit_append_only before delete or update on ops.audit for each row execute function ops.raise_append_only();
create table public.webhook_retries(id uuid primary key,payment_id uuid references public.payments(id));
create table public.disputes(id uuid primary key,payment_id uuid references public.payments(id),transfer_id uuid references public.transfers(id));
create table public.dispute_resolutions(id uuid primary key,transfer_id uuid references public.transfers(id));
create table public.payout_decisions(id uuid primary key,payment_id uuid references public.payments(id) on delete set null,transfer_id uuid references public.transfers(id) on delete cascade);
create table public.seller_flags(id uuid primary key,transfer_id uuid references public.transfers(id) on delete set null);
create table public.transfer_notifications(id uuid primary key,transfer_id uuid references public.transfers(id) on delete cascade);
create table public.payout_attempts(id uuid primary key,payment_id uuid references public.payments(id),transfer_id uuid references public.transfers(id));
create table public.payment_refunds(id uuid primary key,payment_id uuid references public.payments(id));
create trigger trg_payment_refunds_append_only before delete or update on public.payment_refunds for each row execute function ops.raise_append_only();
create table public.payment_refund_state(id uuid primary key,payment_id uuid references public.payments(id));
create table public.payment_refund_state_log(id uuid primary key,payment_id uuid references public.payments(id));
create trigger trg_payment_refund_state_log_append_only before delete or update on public.payment_refund_state_log for each row execute function ops.raise_append_only();
create table public.notifications(id uuid primary key,metadata jsonb);
create table kernel.payment_native(payment_id uuid references public.payments(id) on delete restrict);
create table kernel.refund(payment_id uuid references public.payments(id) on delete restrict);
create table kernel.dispute_native(payment_id uuid references public.payments(id) on delete restrict);
create table market.market_sale(payment_id uuid references public.payments(id) on delete restrict);
grant usage on schema ops to authenticated;

create function ops.refresh_metrics() returns jsonb language sql as $$select '{}'::jsonb$$;

create table ops.alert(alert_key text primary key,state text,payload jsonb,notify_request_id bigint,delivered_at timestamptz);
