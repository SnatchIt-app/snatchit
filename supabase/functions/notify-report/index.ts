/**
 * notify-report — moderation notification pipeline (migration 033)
 *
 * Invoked by DB triggers (via pg_net + Vault service_role_key, same auth
 * pattern as enforce-transfer-expiry) when:
 *   • a row is inserted into public.reports            → event 'report_created'
 *   • a transfer flips to 'disputed'                   → event 'dispute_opened'
 *   • the KMS signing-key invariant monitor alerts      → event 'signing_invariant_alert'
 *     (migration 099, kernel.check_signing_key_invariants — same pg_net +
 *     Vault service_role_key auth, dark until signing.monitor_enabled=true)
 *
 * Actions (all best-effort; failures logged, never thrown to the caller):
 *   1. Push notification to every admin (public.admin_users) — "new report".
 *   2. Push to the involved users: the item/transaction is under review by
 *      Snatch It support; do NOT complete off-platform arrangements.
 *   3. Email via Resend — ONLY when EMAIL_ENABLED === 'true'. Default OFF so
 *      tests and TestFlight never send mail accidentally.
 *      Sender:  EMAIL_FROM   (default "Snatch It <no-reply@snatchitapp.com>")
 *      Admin:   ADMIN_EMAIL  (default "support@snatchitapp.com")
 *   4. SMS: NOT implemented — the project has no SMS provider configured
 *      (verified in the 033 audit). Deliberately not invented here.
 *
 * Privacy: user emails are looked up server-side via auth.admin and used as
 * BCC-style individual sends — never exposed to other users or stored.
 */

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { captureException } from '../_shared/sentry.ts';

const SUPABASE_URL              = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const INTERNAL_CRON_SECRET      = Deno.env.get('INTERNAL_CRON_SECRET') ?? '';
const RESEND_API_KEY            = Deno.env.get('RESEND_API_KEY') ?? '';
const EMAIL_ENABLED             = (Deno.env.get('EMAIL_ENABLED') ?? 'false') === 'true';
const EMAIL_FROM                = Deno.env.get('EMAIL_FROM')  ?? 'Snatch It <no-reply@snatchitapp.com>';
const ADMIN_EMAIL               = Deno.env.get('ADMIN_EMAIL') ?? 'support@snatchitapp.com';

function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/** true when the push was accepted. A non-OK response is a FAILURE: it used to be
 *  ignored entirely, which made "delivered" mean only "we managed to call fetch". */
async function sendPush(supabase: SupabaseClient, userId: string, title: string, body: string, data?: Record<string, string>): Promise<boolean> {
  try {
    const res = await fetch(`${SUPABASE_URL}/functions/v1/send-push`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ user_id: userId, title, body, data }),
    });
    if (!res.ok) { console.error('notify-report: send-push refused', res.status); return false; }
    return true;
  } catch (err) {
    console.error('notify-report: sendPush failed:', err);
    return false;
  }
}

/** null = not attempted (email off, or no key); true/false = attempted and its outcome. */
async function sendEmail(to: string, subject: string, text: string): Promise<boolean | null> {
  if (!EMAIL_ENABLED) {
    console.log(`notify-report: EMAIL_ENABLED=false — skipped email to ${to} ("${subject}")`);
    return null;
  }
  if (!RESEND_API_KEY) {
    console.warn('notify-report: RESEND_API_KEY not set — email skipped');
    return null;
  }
  try {
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${RESEND_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ from: EMAIL_FROM, to: [to], subject, text }),
    });
    if (!res.ok) { console.error('notify-report: Resend error:', res.status, await res.text()); return false; }
    return true;
  } catch (err) {
    console.error('notify-report: email send failed:', err);
    return false;
  }
}

async function emailForUser(supabase: SupabaseClient, userId: string): Promise<string | null> {
  try {
    const { data } = await supabase.auth.admin.getUserById(userId);
    return data?.user?.email ?? null;
  } catch { return null; }
}

const UNDER_REVIEW_COPY =
  'Snatch It support is reviewing this. Please do not complete any arrangements ' +
  'outside the app — keep all communication and the transfer inside Snatch It ' +
  'so you stay covered.';

serve(async (req: Request) => {
  // ── Auth: INTERNAL_CRON_SECRET or runtime service-role key ────────────────
  const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer /, '');
  const ok =
    (INTERNAL_CRON_SECRET.length > 0 && constantTimeEqual(token, INTERNAL_CRON_SECRET)) ||
    (SUPABASE_SERVICE_ROLE_KEY.length > 0 && constantTimeEqual(token, SUPABASE_SERVICE_ROLE_KEY));
  if (!ok) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), {
      status: 401, headers: { 'Content-Type': 'application/json' },
    });
  }

  // Hoisted ABOVE the try so the finally can see them (D review 2). The release
  // must not sit only on the success path: this handler's own work can throw —
  // the admin_users read is the first thing after the claim — and the outer catch
  // answers 200 without releasing, which stranded the claim exactly as before.
  let claimHeld = false;
  let claimKey: string | null = null;
  let event = 'unknown';
  let attempted = 0, delivered = 0;
  const notify = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, { db: { schema: 'notify' } });

  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const payload = await req.json();
    event = payload?.event ?? 'unknown';

    // ── G22: claim the delivery BEFORE sending anything ───────────────────────
    // This function is driven by DB triggers through pg_net and answers 200 even
    // on failure so callers never retry-storm; nothing recorded that an event had
    // already been announced, so a duplicate fire re-sent every push and email.
    //
    // The keys (A, 2026-09-17). report_created and dispute_opened are one-shot
    // and key on their row id. The signing alert does NOT: it fires on a daily
    // cron and repeats with the SAME codes while the trust root stays wrong, so
    // keying it on the alert text would announce a compromise once and silence
    // every later warning. It keys on the RUN — the UTC date, because the edge
    // cannot see the cron runid. Cost, accepted deliberately: two alerts in one
    // UTC day collapse into one. If 099 ever passes a runid, use that instead
    // (A's 137 covers it).
    // TRIGGER, not condition (D): moving 099's schedule to within ~an hour of
    // 00:00 UTC makes this LIVE — a run just after midnight keys to tomorrow and
    // then suppresses tomorrow's alarm. Today 099 is `23 5 * * *` = 05:23 UTC.
    //
    // FAIL TOWARD DELIVERING: only an explicit `false` (someone already
    // announced this) suppresses. A claim that errors sends anyway and logs — a
    // duplicate is a nuisance, a missing under-review notice or a missing
    // trust-root alarm is not.
    claimKey =
      event === 'report_created'          ? (payload?.report_id   != null ? String(payload.report_id)   : null)
      : event === 'dispute_opened'        ? (payload?.transfer_id != null ? String(payload.transfer_id) : null)
      : event === 'signing_invariant_alert' ? new Date().toISOString().slice(0, 10)
      : null;

    // Delivery accounting for the claim above (D's review of bcece84): every send
    // here swallows its error and the handler answers 200, so a claim that is taken
    // and never given back turns "at most once" into "sometimes zero".
    const push = async (userId: string, title: string, body: string, data?: Record<string, string>) => {
      attempted++; if (await sendPush(supabase, userId, title, body, data)) delivered++;
    };
    const mail = async (to: string, subject: string, text: string) => {
      const r = await sendEmail(to, subject, text);
      if (r !== null) { attempted++; if (r) delivered++; }   // email switched off is NOT a failed attempt
    };

    if (claimKey !== null) {
      const { data: claimed, error: claimErr } = await notify.rpc('claim_report_delivery', { p_kind: event, p_key: claimKey });
      if (claimErr) {
        console.warn('notify-report: delivery claim failed, sending anyway', { event, code: claimErr.code ?? null });
      } else if (claimed === false) {
        console.log('notify-report: already announced, skipping', { event });
        return new Response(JSON.stringify({ ok: true, event, duplicate: true }), {
          status: 200, headers: { 'Content-Type': 'application/json' },
        });
      } else {
        claimHeld = true;
      }
    }

    // Admin recipients (allowlist; currently SNATCH IT APP ADMIN)
    const { data: admins } = await supabase.from('admin_users').select('user_id');
    const adminIds: string[] = (admins ?? []).map((a: { user_id: string }) => a.user_id);

    if (event === 'report_created') {
      const { report_id, reporter_id, target_type, target_id, reason } = payload;

      // Resolve the reported party
      let reportedUserId: string | null = null;
      if (target_type === 'user') {
        reportedUserId = target_id;
      } else if (target_type === 'listing') {
        const { data: l } = await supabase.from('listings')
          .select('seller_id').eq('id', target_id).maybeSingle();
        reportedUserId = l?.seller_id ?? null;
      }

      // 1. Admin push + email
      for (const id of adminIds) {
        await push(id, 'New report filed',
          `${target_type} report — reason: ${reason}. Review in the admin dashboard.`,
          { type: 'admin_report', reportId: String(report_id) });
      }
      await mail(ADMIN_EMAIL, `[Snatch It] New ${target_type} report (${reason})`,
        `A new report was filed.\n\nReport ID: ${report_id}\nType: ${target_type}\nTarget: ${target_id}\nReason: ${reason}\n\nReview it in the admin SQL pack / dashboard.`);

      // 2. Reporter: confirmation
      if (reporter_id) {
        await push(reporter_id, 'Report received',
          `Thanks — our team is reviewing your report. ${UNDER_REVIEW_COPY}`,
          { type: 'report_ack' });
        const e = await emailForUser(supabase, reporter_id);
        if (e) await mail(e, 'We received your report',
          `Thanks for the report.\n\n${UNDER_REVIEW_COPY}\n\n— Snatch It Support`);
      }

      // 3. Reported party: under review (neutral copy — no accusation)
      if (reportedUserId && reportedUserId !== reporter_id) {
        const what = target_type === 'listing' ? 'One of your listings' : 'Your profile';
        await push(reportedUserId, 'Under review',
          `${what} is being reviewed by Snatch It support. ${UNDER_REVIEW_COPY}`,
          { type: 'under_review' });
        const e = await emailForUser(supabase, reportedUserId);
        if (e) await mail(e, 'Your Snatch It account: item under review',
          `${what} is currently under review by Snatch It support.\n\n${UNDER_REVIEW_COPY}\n\n— Snatch It Support`);
      }

    } else if (event === 'dispute_opened') {
      const { transfer_id, buyer_id, seller_id, reason } = payload;

      for (const id of adminIds) {
        await push(id, 'Dispute opened',
          `Transfer dispute (${reason}). Review required.`,
          { type: 'admin_dispute', transferId: String(transfer_id) });
      }
      await mail(ADMIN_EMAIL, `[Snatch It] Dispute opened (${reason})`,
        `A transfer dispute was opened.\n\nTransfer: ${transfer_id}\nReason: ${reason}\n\nSee DAY5_ADMIN_DISPUTE_SOP.md.`);

      for (const [id, label] of [[buyer_id, 'buyer'], [seller_id, 'seller']] as const) {
        if (!id) continue;
        await push(id, 'Transaction under review',
          `This transaction is under review by Snatch It support. ${UNDER_REVIEW_COPY}`,
          { type: 'dispute_review', transferId: String(transfer_id), role: label });
        const e = await emailForUser(supabase, id);
        if (e) await mail(e, 'Your Snatch It transaction is under review',
          `A dispute was opened on one of your transactions and Snatch It support is reviewing it.\n\n${UNDER_REVIEW_COPY}\n\n— Snatch It Support`);
      }

    } else if (event === 'signing_invariant_alert') {
      // KJ §4.5 / migration 099. alerts is an array of short words/counts
      // only (e.g. "total_keys=2", "fingerprint=MISMATCH") — never key
      // material, never a KMS handle, never the raw fingerprint hex; the DB
      // function reduces those to a comparison result before this ever
      // fires. No named person: admin push fan-out + ADMIN_EMAIL + Sentry.
      const alerts: string[] = Array.isArray(payload?.alerts) ? payload.alerts : [];
      const summary = alerts.length > 0 ? alerts.join(', ') : '(no alert codes provided)';

      for (const id of adminIds) {
        await push(id, 'Signing-key invariant alert',
          `KMS signing-key monitor: ${summary}`,
          { type: 'signing_invariant_alert' });
      }
      await mail(ADMIN_EMAIL, '[Snatch It] Signing-key invariant alert',
        `The KMS signing-key invariant monitor (kernel.check_signing_key_invariants, migration 099) fired:\n\n${summary}\n\nSee docs/phase2/PRODUCTION_SIGNING_KMS_CEREMONY.md §4 and docs/phase2/_impl/KJ_kms_runbook_monitor.md.`);

      await captureException('signing-monitor', new Error('signing_invariant_alert: ' + summary));

    } else {
      console.warn('notify-report: unknown event', event);
    }

    return new Response(JSON.stringify({ ok: true, event }), {
      status: 200, headers: { 'Content-Type': 'application/json' },
    });
  } catch (err) {
    console.error('notify-report: error:', err);
    // 200 so pg_net callers never retry-storm; the trigger is fire-and-forget.
    return new Response(JSON.stringify({ ok: false }), {
      status: 200, headers: { 'Content-Type': 'application/json' },
    });
  } finally {
    // Nothing landed on any channel: give the claim back so the next delivery of
    // this event tries again. A PARTIAL success keeps it (delivered > 0), so the
    // normal path still cannot duplicate. The condition is `delivered === 0`, NOT
    // `attempted > 0 && delivered === 0` (D): the claim asserts "this delivery has
    // been announced", and zero deliveries means it has not — including the case
    // where the handler threw before attempting anything. The cost is churn when
    // there is genuinely nothing to send (no admins, email off), and that is the
    // right trade: a notify-report with no configured recipient is a
    // misconfiguration that should keep showing up, not one that quietly claims
    // success. signing_invariant_alert would self-heal tomorrow through its run
    // key; report_created and dispute_opened have no next run.
    if (claimHeld && claimKey !== null && delivered === 0) {
      const { error: relErr } = await notify.rpc('release_report_delivery', { p_kind: event, p_key: claimKey });
      console.warn('notify-report: nothing delivered — claim released for retry', { event, released: !relErr, attempted });
    }
  }
});
