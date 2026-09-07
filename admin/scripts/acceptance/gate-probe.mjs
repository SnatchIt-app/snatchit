#!/usr/bin/env node
// ============================================================================
// Operating console — founder-run acceptance probe (G1-verify, G2, G3, G4, G5,
// G6, G8). Zero dependencies. Run it on YOUR machine, never in chat:
//
//   SUPABASE_URL=https://<project>.supabase.co \
//   SUPABASE_ANON_KEY=<publishable key> \
//   node admin/scripts/acceptance/gate-probe.mjs
//
// It prompts for the email, password and (if enrolled) TOTP code of the
// account to test — typed locally, never echoed, never stored, sent only to
// the Supabase Auth API of the project you named — and prints PASS/FAIL lines.
// Run it once as each FOUNDER and once as a NON-OPERATOR account. It performs
// no mutation except one attempt to open a synthetic case, which the server
// must refuse for non-operators / aal1 sessions and which a founder may keep
// or dismiss afterwards (G7 is exercised from the console UI, see
// ACCEPTANCE_GATES.md).
// ============================================================================
import readline from 'node:readline';
import { stdin as input, stdout as output } from 'node:process';

const URL = process.env.SUPABASE_URL, ANON = process.env.SUPABASE_ANON_KEY;
if (!URL || !ANON) { console.error('set SUPABASE_URL and SUPABASE_ANON_KEY'); process.exit(2); }
const rl = readline.createInterface({ input, output, terminal: true });
const ask = (q, hidden = false) => new Promise((res) => {
  if (!hidden) return rl.question(q, res);
  output.write(q);
  if (input.setRawMode) input.setRawMode(true);
  let buf = '';
  const onData = (ch) => {
    const c = ch.toString();
    if (c === '\n' || c === '\r') { if (input.setRawMode) input.setRawMode(false); input.removeListener('data', onData); output.write('\n'); res(buf); }
    else if (c === '\u0003') process.exit(1);
    else if (c === '\u007f' || c === '\b') buf = buf.slice(0, -1);
    else buf += c;
  };
  input.on('data', onData);
});
const results = [];
const gate = (id, ok, detail) => { results.push([id, ok]); console.log(`${ok ? 'PASS' : 'FAIL'}  ${id}  ${detail}`); };
const api = (path, token, opts = {}) => fetch(`${URL}${path}`, { ...opts, headers: { apikey: ANON, Authorization: `Bearer ${token ?? ANON}`, 'Content-Type': 'application/json', ...(opts.headers ?? {}) } });
const rpc = (fn, token, args = {}) => api(`/rest/v1/rpc/${fn}`, token, { method: 'POST', headers: { 'Content-Profile': 'ops' }, body: JSON.stringify(args) });
const claims = (jwt) => JSON.parse(Buffer.from(jwt.split('.')[1], 'base64url').toString());
const probeCase = (token) => rpc('execute_action', token, { p_idempotency_key: `gate-probe-${Date.now()}`, p_action_type: 'case_create', p_subject_kind: 'none', p_subject_id: null, p_params: { title: 'acceptance probe (safe to dismiss)' }, p_reason: 'acceptance probe' });

const email = await ask('Account email to test: ');
const password = await ask('Password (not echoed): ', true);
let r = await api('/auth/v1/token?grant_type=password', undefined, { method: 'POST', body: JSON.stringify({ email, password }) });
if (!r.ok) { console.error('sign-in failed:', r.status); process.exit(1); }
let session = await r.json();
let c = claims(session.access_token);
console.log(`signed in · aal=${c.aal} · sub=${String(c.sub).slice(0, 8)}…`);

if (c.aal !== 'aal2') {
  // G3 — lower-assurance session: protected reads and mutations must be refused
  const list = await rpc('list_cases', session.access_token, { p_filters: {}, p_limit: 1 });
  gate('G3-protected-read', !list.ok && /step_up|insufficient/.test(await list.text()), `list_cases at aal1 → ${list.status} (expect step_up refusal)`);
  const mut = await probeCase(session.access_token);
  gate('G3-mutation', !mut.ok && /step_up|insufficient/.test(await mut.text()), `execute_action at aal1 → ${mut.status} (expect refusal)`);
  const factors = await api('/auth/v1/factors', session.access_token);
  const fj = factors.ok ? await factors.json() : [];
  const totp = (Array.isArray(fj) ? fj : fj.totp ?? []).find((f) => f.status === 'verified');
  if (totp) {
    const ch = await api(`/auth/v1/factors/${totp.id}/challenge`, session.access_token, { method: 'POST', body: '{}' });
    const chj = await ch.json();
    const code = await ask('TOTP code from your authenticator (not stored): ', true);
    const v = await api(`/auth/v1/factors/${totp.id}/verify`, session.access_token, { method: 'POST', body: JSON.stringify({ challenge_id: chj.id, code }) });
    if (v.ok) { session = await v.json(); c = claims(session.access_token); gate('G1-verify', c.aal === 'aal2', `real TOTP verified → aal=${c.aal}`); }
    else gate('G1-verify', false, `TOTP verification failed (${v.status})`);
  } else {
    console.log('no verified TOTP factor on this account — enrol in the console first (G1), then rerun');
  }
}

if (c.aal === 'aal2') {
  const who = await rpc('whoami', session.access_token);
  const body = await who.text();
  const isOperator = who.ok && /"role"\s*:\s*"platform_/.test(body);
  if (isOperator) {
    gate('G1-operator', true, 'operator role recognised at aal2');
    const anyProof = await api('/storage/v1/object/list/proof-docs', session.access_token, { method: 'POST', body: JSON.stringify({ prefix: '', limit: 5 }) });
    const lj = anyProof.ok ? await anyProof.json() : [];
    gate('G5-listing-scope', anyProof.ok, `proof-docs list as operator → ${anyProof.status}, ${Array.isArray(lj) ? lj.length : 0} object(s) visible (only referenced evidence may appear)`);
    const badSlot = await rpc('evidence_access', session.access_token, { p_subject_kind: 'transfer', p_subject_id: '00000000-0000-0000-0000-000000000000', p_slot: 'cover_image' });
    gate('G5-bad-slot', !badSlot.ok, `evidence_access with an invalid slot → ${badSlot.status} (expect refusal)`);
    const badBucket = await api('/storage/v1/object/sign/avatars/does-not-exist.jpg', session.access_token, { method: 'POST', body: JSON.stringify({ expiresIn: 60 }) });
    gate('G5-arbitrary-path', !badBucket.ok, `signing an arbitrary path in another bucket → ${badBucket.status} (expect 4xx)`);
    const fn = await api('/functions/v1/ops-refund-execute', session.access_token, { method: 'POST', body: JSON.stringify({ action_id: '00000000-0000-0000-0000-000000000000' }) });
    gate('G8-endpoint-absent', fn.status === 404, `ops-refund-execute → ${fn.status} (expect 404: not deployed)`);
    const setting = await rpc('settings', session.access_token);
    const sj = setting.ok ? await setting.json() : null;
    const rf = Array.isArray(sj) ? sj.find((s) => s.key === 'refund_execute_enabled') : null;
    gate('G8-setting', rf ? rf.value === false : false, `refund_execute_enabled = ${rf ? JSON.stringify(rf.value) : 'unreadable (platform_admin only)'}`);
    const tid = await ask('G4/G6: transfer id with recorded evidence where you are neither buyer nor seller (blank to skip): ');
    if (tid) {
      const ev = await rpc('evidence_access', session.access_token, { p_subject_kind: 'transfer', p_subject_id: tid, p_slot: 'transfer_evidence' });
      if (ev.ok) {
        const e = await ev.json();
        const sign = await api(`/storage/v1/object/sign/${e.bucket}/${e.path}`, session.access_token, { method: 'POST', body: JSON.stringify({ expiresIn: 60 }) });
        if (sign.ok) {
          const s = await sign.json();
          const signed = `${URL}/storage/v1${s.signedURL}`;
          const now = await fetch(signed);
          gate('G4-open', now.ok, `signed evidence URL → ${now.status} (60 s TTL for this probe)`);
          console.log('waiting 70 s to prove expiry…');
          await new Promise((res) => setTimeout(res, 70000));
          const later = await fetch(signed);
          gate('G6-expiry', !later.ok, `same URL after 70 s → ${later.status} (expect 4xx)`);
        } else gate('G4-open', false, `createSignedUrl → ${sign.status}`);
      } else gate('G4-open', false, `evidence_access → ${ev.status} ${await ev.text()}`);
    }
  } else {
    gate('G2-whoami', !who.ok && /insufficient_privilege/.test(body), `whoami as non-operator → ${who.status} (expect 42501)`);
    const list = await rpc('list_cases', session.access_token, { p_filters: {}, p_limit: 1 });
    gate('G2-read', !list.ok, `list_cases as non-operator → ${list.status}`);
    const mut = await probeCase(session.access_token);
    gate('G2-mutation', !mut.ok, `execute_action as non-operator → ${mut.status}`);
    const proof = await api('/storage/v1/object/list/proof-docs', session.access_token, { method: 'POST', body: JSON.stringify({ prefix: '', limit: 5 }) });
    const pj = proof.ok ? await proof.json() : [];
    gate('G5-unrelated', !proof.ok || (Array.isArray(pj) && pj.length === 0), `proof-docs list as unrelated user → ${proof.status}, ${Array.isArray(pj) ? pj.length : '?'} object(s) (expect 0)`);
  }
}
await api('/auth/v1/logout', session.access_token, { method: 'POST', body: '{}' }).catch(() => {});
rl.close();
console.log(`\n${results.filter((x) => x[1]).length}/${results.length} gates passed for this account.`);
