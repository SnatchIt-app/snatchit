// READY TO DEPLOY
import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

const SUPABASE_URL             = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const EXPO_PUSH_URL            = Deno.env.get('EXPO_PUSH_URL') ?? 'https://exp.host/--/api/v2/push/send';

// ── Authorization ─────────────────────────────────────────────────────────────
// send-push is an internal-only function. It must only be called by trusted
// server-side callers (currently: stripe-webhook edge function).
// We verify the caller presents the service-role key as the Bearer token.
// Mobile clients hold only the anon key and cannot forge this value.
function isAuthorized(req: Request): boolean {
  const authHeader = req.headers.get('Authorization') ?? '';
  if (!authHeader.startsWith('Bearer ')) return false;
  const token = authHeader.slice('Bearer '.length);
  // Constant-time comparison to prevent timing attacks
  if (token.length !== SUPABASE_SERVICE_ROLE_KEY.length) return false;
  let diff = 0;
  for (let i = 0; i < token.length; i++) {
    diff |= token.charCodeAt(i) ^ SUPABASE_SERVICE_ROLE_KEY.charCodeAt(i);
  }
  return diff === 0;
}

// ── Handler ───────────────────────────────────────────────────────────────────

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { status: 200 });
  }

  // Reject any caller that is not presenting the service-role key.
  if (!isAuthorized(req)) {
    return new Response(
      JSON.stringify({ error: 'Unauthorized' }),
      { status: 401, headers: { 'Content-Type': 'application/json' } },
    );
  }

  try {
    const { user_id, title, body, data } = await req.json();

    if (!user_id || !title || !body) {
      return new Response(
        JSON.stringify({ error: 'Missing user_id, title, or body' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      );
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    const { data: tokens, error: tokensErr } = await supabase
      .from('push_tokens')
      .select('token')
      .eq('user_id', user_id)
      .eq('is_active', true)
      .not('token', 'is', null);

    if (tokensErr || !tokens || tokens.length === 0) {
      return new Response(
        JSON.stringify({ sent: 0, reason: 'No push tokens found' }),
        { status: 200, headers: { 'Content-Type': 'application/json' } }
      );
    }

    const messages = tokens.map((t: { token: string }) => ({
      to: t.token,
      title,
      body,
      data: data ?? {},
      sound: 'default' as const,
    }));

    const pushRes = await fetch(EXPO_PUSH_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(messages),
    });

    const pushData = await pushRes.json();

    return new Response(
      JSON.stringify({ sent: messages.length, results: pushData }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    );
  } catch (err) {
    console.error('send-push error:', err);
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    );
  }
});
