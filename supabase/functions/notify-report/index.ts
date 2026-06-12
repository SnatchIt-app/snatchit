/**
 * notify-report — moderation notification pipeline (migration 033)
 *
 * Invoked by DB triggers (via pg_net + Vault service_role_key, same auth
 * pattern as enforce-transfer-expiry) when:
 *   • a row is inserted into public.reports            → event 'report_created'
 *   • a transfer flips to 'disputed'                   → event 'dispute_opened'
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
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

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

async function sendPush(supabase: ReturnType<typeof createClient>, userId: string, title: string, body: string, data?: Record<string, string>) {
  try {
    await fetch(`${SUPABASE_URL}/functions/v1/send-push`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ user_id: userId, title, body, data }),
    });
  } catch (err) {
    console.error('notify-report: sendPush failed:', err);
  }
}

async function sendEmail(to: string, subject: string, text: string) {
  if (!EMAIL_ENABLED) {
    console.log(`notify-report: EMAIL_ENABLED=false — skipped email to ${to} ("${subject}")`);
    return;
  }
  if (!RESEND_API_KEY) {
    console.warn('notify-report: RESEND_API_KEY not set — email skipped');
    return;
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
    if (!res.ok) console.error('notify-report: Resend error:', res.status, await res.text());
  } catch (err) {
    console.error('notify-report: email send failed:', err);
  }
}

async function emailForUser(supabase: ReturnType<typeof createClient>, userId: string): Promise<string | null> {
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

  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const payload = await req.json();
    const event: string = payload?.event ?? 'unknown';

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
        await sendPush(supabase, id, 'New report filed',
          `${target_type} report — reason: ${reason}. Review in the admin dashboard.`,
          { type: 'admin_report', reportId: String(report_id) });
      }
      await sendEmail(ADMIN_EMAIL, `[Snatch It] New ${target_type} report (${reason})`,
        `A new report was filed.\n\nReport ID: ${report_id}\nType: ${target_type}\nTarget: ${target_id}\nReason: ${reason}\n\nReview it in the admin SQL pack / dashboard.`);

      // 2. Reporter: confirmation
      if (reporter_id) {
        await sendPush(supabase, reporter_id, 'Report received',
          `Thanks — our team is reviewing your report. ${UNDER_REVIEW_COPY}`,
          { type: 'report_ack' });
        const e = await emailForUser(supabase, reporter_id);
        if (e) await sendEmail(e, 'We received your report',
          `Thanks for the report.\n\n${UNDER_REVIEW_COPY}\n\n— Snatch It Support`);
      }

      // 3. Reported party: under review (neutral copy — no accusation)
      if (reportedUserId && reportedUserId !== reporter_id) {
        const what = target_type === 'listing' ? 'One of your listings' : 'Your profile';
        await sendPush(supabase, reportedUserId, 'Under review',
          `${what} is being reviewed by Snatch It support. ${UNDER_REVIEW_COPY}`,
          { type: 'under_review' });
        const e = await emailForUser(supabase, reportedUserId);
        if (e) await sendEmail(e, 'Your Snatch It account: item under review',
          `${what} is currently under review by Snatch It support.\n\n${UNDER_REVIEW_COPY}\n\n— Snatch It Support`);
      }

    } else if (event === 'dispute_opened') {
      const { transfer_id, buyer_id, seller_id, reason } = payload;

      for (const id of adminIds) {
        await sendPush(supabase, id, 'Dispute opened',
          `Transfer dispute (${reason}). Review required.`,
          { type: 'admin_dispute', transferId: String(transfer_id) });
      }
      await sendEmail(ADMIN_EMAIL, `[Snatch It] Dispute opened (${reason})`,
        `A transfer dispute was opened.\n\nTransfer: ${transfer_id}\nReason: ${reason}\n\nSee DAY5_ADMIN_DISPUTE_SOP.md.`);

      for (const [id, label] of [[buyer_id, 'buyer'], [seller_id, 'seller']] as const) {
        if (!id) continue;
        await sendPush(supabase, id, 'Transaction under review',
          `This transaction is under review by Snatch It support. ${UNDER_REVIEW_COPY}`,
          { type: 'dispute_review', transferId: String(transfer_id), role: label });
        const e = await emailForUser(supabase, id);
        if (e) await sendEmail(e, 'Your Snatch It transaction is under review',
          `A dispute was opened on one of your transactions and Snatch It support is reviewing it.\n\n${UNDER_REVIEW_COPY}\n\n— Snatch It Support`);
      }

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
  }
});
