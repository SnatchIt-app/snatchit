/**
 * 140 client adaptation — Mark as sent reads transitioned | already_sent; a transfer sent without
 * a screenshot gets the explicit Add proof action (attach_transfer_evidence → attached |
 * already_attached); every server text the client keys on is pinned against the migrations.
 *
 * Owner's evidence line (2026-09-18): database outcomes 1 and 2 passed on the server side (A/B/D);
 * conversion and buyer display are unverified until a real iPhone round trip; device behaviour needs
 * a build; nobody describes the image issue as fixed. These are automated client results only.
 */
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it, vi } from 'vitest';

import {
  ATTACH_COPY, isSentWithoutProofRaise, MARK_SENT_COPY, parseProofReply, PROOF_LITERALS, runAttachEvidence, runMarkSent,
  type TransferSnapshot,
} from '@/src/lib/transfer/markSent';

const ROOT = resolve(__dirname, '..');
const read = (p: string) => readFileSync(resolve(ROOT, p), 'utf8');
const stripComments = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '').replace(/\{\/\*[\s\S]*?\*\/\}/g, '');

const P = 'u1/transfer-evidence/1789600000000.jpg';
const OTHER = 'u1/transfer-evidence/1789500000000.jpg';
const snap = (status: string, evidencePath: string | null = null): TransferSnapshot => ({ status, evidencePath });
const seq = (...xs: (TransferSnapshot | null | Error)[]) => vi.fn(async () => {
  const x = xs.length > 1 ? xs.shift()! : xs[0];
  if (x instanceof Error) throw x;
  return x;
});
const reply = (outcome: string, status: string, path: string | null) => ({ outcome, status, transfer_evidence_path: path, evidence_replaced: false });

describe('parseProofReply', () => {
  it('reads outcome, status and path; anything else is null', () => {
    expect(parseProofReply(reply('transitioned', 'seller_sent', P))).toEqual({ outcome: 'transitioned', status: 'seller_sent', path: P });
    expect(parseProofReply({ outcome: 'already_sent', status: 'seller_sent', transfer_evidence_path: null })).toEqual({ outcome: 'already_sent', status: 'seller_sent', path: null });
    expect(parseProofReply(null)).toBeNull();
    expect(parseProofReply([reply('attached', 'seller_sent', P)])).toBeNull();
    expect(parseProofReply({ status: 'seller_sent' })).toBeNull();
    expect(parseProofReply('transitioned')).toBeNull();
  });
});

describe('Mark as sent against 140', () => {
  const mk = (readTransfer: () => Promise<TransferSnapshot | null>, call?: (p: string) => Promise<{ data?: unknown; error: { message: string } | null }>) => ({
    readTransfer,
    upload: vi.fn(async () => P),
    call: call ? vi.fn(call) : vi.fn(async () => ({ data: reply('transitioned', 'seller_sent', P), error: null })),
  });

  it('transitioned and read back sent with the proof → sent', async () => {
    const d = mk(seq(snap('pending'), snap('seller_sent', P)));
    expect(await runMarkSent(d)).toEqual({ kind: 'sent', path: P });
    expect(d.upload).toHaveBeenCalledTimes(1);
    expect(d.call).toHaveBeenCalledTimes(1);
  });

  it('a lost response retried: already_sent keeps the original proof → sent with the ORIGINAL path', async () => {
    const d = mk(seq(null, snap('seller_sent', OTHER)), async () => ({ data: reply('already_sent', 'seller_sent', OTHER), error: null }));
    expect(await runMarkSent(d)).toEqual({ kind: 'sent', path: OTHER });
  });

  it('the read-back fails: the server reply is the authoritative answer (transitioned / already_sent)', async () => {
    expect(await runMarkSent(mk(seq(snap('pending'), null)))).toEqual({ kind: 'sent', path: P });
    expect(await runMarkSent(mk(seq(snap('pending'), null), async () => ({ data: reply('already_sent', 'seller_sent', OTHER), error: null })))).toEqual({ kind: 'sent', path: OTHER });
    // no reply, no read → unconfirmed
    expect(await runMarkSent(mk(seq(snap('pending'), null), async () => ({ error: null })))).toEqual({ kind: 'unconfirmed' });
    // a reply that is not one of the two outcomes is not a confirmation
    expect(await runMarkSent(mk(seq(snap('pending'), null), async () => ({ data: reply('queued', 'seller_sent', P), error: null })))).toEqual({ kind: 'unconfirmed' });
  });

  it('a reply claiming "transitioned" that the read contradicts is unconfirmed, never success', async () => {
    expect(await runMarkSent(mk(seq(snap('pending'), snap('pending'))))).toEqual({ kind: 'unconfirmed' });
  });

  it('sent without a screenshot, seen BEFORE: needs the explicit Add proof action; nothing uploaded or called', async () => {
    const d = mk(seq(snap('seller_sent', null)));
    expect(await runMarkSent(d)).toEqual({ kind: 'needs_proof' });
    expect(d.upload).not.toHaveBeenCalled();
    expect(d.call).not.toHaveBeenCalled();
  });

  it('sent without a screenshot, told by the verb\'s raise: needs_proof, one upload only (the hook reuses it for Add proof)', async () => {
    const d = mk(seq(null, snap('seller_sent', null)), async () => ({ error: { message: `precondition_failed: ${PROOF_LITERALS.sentWithoutProof}` } }));
    expect(await runMarkSent(d)).toEqual({ kind: 'needs_proof' });
    expect(d.upload).toHaveBeenCalledTimes(1);
    expect(isSentWithoutProofRaise(`precondition_failed: ${PROOF_LITERALS.sentWithoutProof}`)).toBe(true);
    // the raise alone routes it, even when neither read succeeds
    const blind = mk(seq(null, null), async () => ({ error: { message: `precondition_failed: ${PROOF_LITERALS.sentWithoutProof}` } }));
    expect(await runMarkSent(blind)).toEqual({ kind: 'needs_proof' });
  });

  it('read back seller_sent with no proof (a 2-argument older client raced us) → needs_proof, not sent', async () => {
    expect(await runMarkSent(mk(seq(snap('pending'), snap('seller_sent', null))))).toEqual({ kind: 'needs_proof' });
  });

  it('the conflicting retry (disputed, reversed…) raises and reads back not sent → failed with the server text', async () => {
    const d = mk(seq(snap('pending'), snap('disputed')), async () => ({ error: { message: 'Transfer cannot be marked as sent from current status: disputed.' } }));
    expect(await runMarkSent(d)).toEqual({ kind: 'failed', message: 'Transfer cannot be marked as sent from current status: disputed.' });
  });

  it('contract plumbing texts are never shown to a seller', async () => {
    const d = mk(seq(snap('pending'), snap('pending')), async () => ({ error: { message: 'precondition_failed: something internal' } }));
    expect(await runMarkSent(d)).toEqual({ kind: 'failed', message: MARK_SENT_COPY.failedFallback });
  });
});

describe('Add proof (attach_transfer_evidence) against 140', () => {
  const mk = (readTransfer: () => Promise<TransferSnapshot | null>, attach?: (p: string) => Promise<{ data?: unknown; error: { message: string } | null }>) => ({
    readTransfer,
    upload: vi.fn(async () => P),
    attach: attach ? vi.fn(attach) : vi.fn(async () => ({ data: reply('attached', 'seller_sent', P), error: null })),
  });

  it('attached and read back with the same proof → attached', async () => {
    const d = mk(seq(snap('seller_sent', null), snap('seller_sent', P)));
    expect(await runAttachEvidence(d)).toEqual({ kind: 'attached', path: P });
    expect(d.upload).toHaveBeenCalledTimes(1);
  });

  it('a retry after a lost response: already_attached → attached, no second object', async () => {
    const d = mk(seq(null, snap('seller_sent', P)), async () => ({ data: reply('already_attached', 'seller_sent', P), error: null }));
    expect(await runAttachEvidence(d)).toEqual({ kind: 'attached', path: P });
  });

  it('already has proof BEFORE: nothing uploaded or attached', async () => {
    const d = mk(seq(snap('seller_sent', OTHER)));
    expect(await runAttachEvidence(d)).toEqual({ kind: 'has_proof', path: OTHER });
    expect(d.upload).not.toHaveBeenCalled();
    expect(d.attach).not.toHaveBeenCalled();
  });

  it('not a sent transfer BEFORE (pending, buyer_confirmed…): not eligible, nothing uploaded', async () => {
    for (const st of ['pending', 'buyer_confirmed', 'auto_released', 'disputed']) {
      const d = mk(seq(snap(st, null)));
      expect(await runAttachEvidence(d)).toEqual({ kind: 'not_eligible', status: st });
      expect(d.upload).not.toHaveBeenCalled();
    }
  });

  it('a different proof landed first (append-only refusal): read back → has_proof with the stored path', async () => {
    const d = mk(seq(snap('seller_sent', null), snap('seller_sent', OTHER)), async () => ({ error: { message: 'transfer_evidence_path is append-only.' } }));
    expect(await runAttachEvidence(d)).toEqual({ kind: 'has_proof', path: OTHER });
  });

  it('append-only refusal with a failed read → has_proof; with a read showing no proof → unconfirmed (contradiction)', async () => {
    expect(await runAttachEvidence(mk(seq(snap('seller_sent', null), null), async () => ({ error: { message: 'transfer_evidence_path is append-only.' } })))).toEqual({ kind: 'has_proof', path: null });
    expect(await runAttachEvidence(mk(seq(snap('seller_sent', null), snap('seller_sent', null)), async () => ({ error: { message: 'transfer_evidence_path is append-only.' } })))).toEqual({ kind: 'unconfirmed' });
  });

  it('status changed meanwhile: the "only to a sent transfer" refusal → not_eligible', async () => {
    const msg = `precondition_failed: ${PROOF_LITERALS.attachNotSent} (status: buyer_confirmed)`;
    expect(await runAttachEvidence(mk(seq(snap('seller_sent', null), snap('buyer_confirmed', null)), async () => ({ error: { message: msg } })))).toEqual({ kind: 'not_eligible', status: 'buyer_confirmed' });
    expect(await runAttachEvidence(mk(seq(snap('seller_sent', null), null), async () => ({ error: { message: msg } })))).toEqual({ kind: 'not_eligible', status: null });
  });

  it('other refusals (own folder, transfer-evidence/, no such object) → failed with seller-safe copy, never the raw text', async () => {
    for (const m of ["precondition_failed: evidence path must be inside the caller's own folder", 'precondition_failed: evidence path must be under transfer-evidence/', 'precondition_failed: no such object in proof-docs', 'insufficient_privilege: only the seller can attach evidence']) {
      expect(await runAttachEvidence(mk(seq(snap('seller_sent', null), snap('seller_sent', null)), async () => ({ error: { message: m } })))).toEqual({ kind: 'failed', message: ATTACH_COPY.failedFallback });
    }
  });

  it('attach throws or times out: the read decides; a claimed attach the read doesn\'t show is unconfirmed', async () => {
    expect(await runAttachEvidence(mk(seq(snap('seller_sent', null), snap('seller_sent', P)), async () => { throw new Error('timeout'); }))).toEqual({ kind: 'attached', path: P });
    expect(await runAttachEvidence(mk(seq(snap('seller_sent', null), snap('seller_sent', null)), async () => { throw new Error('timeout'); }))).toEqual({ kind: 'unconfirmed' });
    expect(await runAttachEvidence(mk(seq(snap('seller_sent', null), null), async () => { throw new Error('timeout'); }))).toEqual({ kind: 'unconfirmed' });
    // read fails, reply says attached for a DIFFERENT path → not a confirmation of ours
    expect(await runAttachEvidence(mk(seq(snap('seller_sent', null), null), async () => ({ data: reply('attached', 'seller_sent', OTHER), error: null })))).toEqual({ kind: 'unconfirmed' });
    // read fails, reply attached for OUR path → attached
    expect(await runAttachEvidence(mk(seq(snap('seller_sent', null), null)))).toEqual({ kind: 'attached', path: P });
  });

  it('upload failed → no attach', async () => {
    const d = { readTransfer: seq(snap('seller_sent', null)), upload: vi.fn(async () => null), attach: vi.fn(async () => ({ error: null })) };
    expect(await runAttachEvidence(d)).toEqual({ kind: 'upload_failed' });
    expect(d.attach).not.toHaveBeenCalled();
  });
});

describe('every server text and name the client keys on exists in the migrations', () => {
  const m140 = read('supabase/migrations/140_proof_upload_repair.sql');
  const guardFiles = readdirSync(resolve(ROOT, 'supabase/migrations')).filter((f) => f.endsWith('.sql'));
  const guards = guardFiles.map((f) => read(`supabase/migrations/${f}`)).join('\n');
  it('140 raises and outcomes', () => {
    expect(m140).toContain(`raise exception 'precondition_failed: ${PROOF_LITERALS.sentWithoutProof}'`);
    expect(m140).toContain(`raise exception 'Transfer ${PROOF_LITERALS.cannotMarkFrom} %.'`);
    expect(m140).toContain(`raise exception 'precondition_failed: ${PROOF_LITERALS.attachNotSent} (status: %)'`);
    for (const o of ["'outcome', 'transitioned'", "'outcome', 'already_sent'", "('outcome', 'attached'", "('outcome', 'already_attached'"]) expect(m140).toContain(o);
    expect(m140).toContain("'transfer_evidence_path', v_path");
    expect(m140).toContain('create or replace function public.attach_transfer_evidence(p_transfer_id uuid, p_transfer_evidence_path text)');
    expect(m140).toContain('create function public.mark_transfer_sent(p_transfer_id uuid, p_user_id uuid, p_transfer_evidence_path text)');
  });
  it('the append-only guard text', () => {
    expect(guards).toContain(`RAISE EXCEPTION '${PROOF_LITERALS.appendOnly}.'`);
  });
  it('the screen calls both verbs with exactly those parameter names and reads the stored proof', () => {
    const send = stripComments(read('app/transfer/send/[id].tsx'));
    expect(send).toContain("supabase.rpc('mark_transfer_sent', { p_transfer_id: id, p_user_id: userId, p_transfer_evidence_path: path })");
    expect(send).toContain("supabase.rpc('attach_transfer_evidence', { p_transfer_id: id, p_transfer_evidence_path: path })");
    expect(send).toContain(".select('status, transfer_evidence_path')");
    expect(send.split('return { data, error: rpcErr ? { message: rpcErr.message } : null };').length - 1).toBe(2);
  });
});

describe('the send screen (source contract; rendering is a device row)', () => {
  const send = stripComments(read('app/transfer/send/[id].tsx'));
  it('Add proof shows only for a sent transfer with no stored proof, single-flight, with the same photo control', () => {
    const at = send.indexOf("transfer.status === 'seller_sent' && !transfer.transfer_evidence_path ? (");
    expect(at).toBeGreaterThan(-1);
    const block = send.slice(at, send.indexOf(') : null}', at));
    expect(block).toContain('ATTACH_COPY.title');
    expect(block).toContain('<MediaUpload');
    expect(block).toContain('onPress={handleAttachProof}');
    const h = send.slice(send.indexOf('async function handleAttachProof()'), send.indexOf('const onRefresh = useCallback('));
    expect(h).toContain('await flight.run(');
    expect(h).toContain('runAttachEvidence(');
    // success only on "attached"; the photo is cleared only then
    const ok = h.indexOf("if (outcome.kind === 'attached') {");
    expect(ok).toBeGreaterThan(-1);
    expect(h.indexOf('evidenceUpload.reset();')).toBeGreaterThan(ok);
    expect(h.indexOf("Alert.alert('Proof added'")).toBeGreaterThan(ok);
    expect(h.split('evidenceUpload.reset();').length - 1).toBe(1);
  });
  it('needs_proof keeps the chosen photo and routes to Add proof; it is never shown as "Marked as sent"', () => {
    const h = send.slice(send.indexOf('async function handleMarkSent()'), send.indexOf('async function readTransfer()'));
    const np = h.indexOf("if (outcome.kind === 'needs_proof') {");
    expect(np).toBeGreaterThan(-1);
    const npBlock = h.slice(np, h.indexOf('return;', np));
    expect(npBlock).toContain('MARK_SENT_COPY.needsProof');
    expect(npBlock).not.toContain('evidenceUpload.reset()');
    expect(npBlock).not.toContain("'Marked as sent'");
  });
  it('"Pull down to refresh" is true on this screen', () => {
    expect(MARK_SENT_COPY.unconfirmed).toMatch(/Pull down to refresh/);
    expect(ATTACH_COPY.unconfirmed).toMatch(/Pull down to refresh/);
    expect(send).toContain('refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh}');
  });
});
