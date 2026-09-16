/**
 * tests/push-classifier-migration-guard.test.ts — the client's push error
 * classifiers key on exact `raise exception` texts and 200-reply literals that
 * live in A's migration 135. A reword there would degrade the client silently
 * to `unknown` and no other test in either half catches it (D, 2026-09-16).
 * This test lives on the combined stack, where 135 exists, and fails loudly
 * in CI if any keyed string leaves the migration body.
 *
 * Not asserted (dead branches at v3, kept for contract-v2 servers): the
 * `nonce mismatch` raise and `token is bound to another account`.
 */

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

import { classifyChallengeError, interpretConfirmReply, type ChallengeErrorKind } from '@/src/lib/push/challenge';
import { classifyRegistrationError } from '@/src/lib/push/registration';

const MIGRATION = 'supabase/migrations/135_push_token_proof_of_possession.sql';
const sql = readFileSync(resolve(__dirname, '..', MIGRATION), 'utf8');

type Raised = { code: 'P0001' | '42501'; text: string; challenge?: ChallengeErrorKind; registration?: ReturnType<typeof classifyRegistrationError> };

// Every raise the client classifies, exactly as 135 raises it.
const RAISED: Raised[] = [
  { code: '42501', text: 'not_authenticated', challenge: 'auth', registration: 'auth' },
  { code: '42501', text: 'insufficient_privilege: session predates a credential change', challenge: 'session_stale', registration: 'session_stale' },
  { code: '42501', text: 'insufficient_privilege: challenge belongs to another session', challenge: 'other_session' },
  { code: 'P0001', text: 'precondition_failed: challenge expired', challenge: 'expired' },
  { code: 'P0001', text: 'precondition_failed: challenge consumed', challenge: 'consumed' },
  { code: 'P0001', text: 'precondition_failed: challenge not found', challenge: 'consumed' },
  { code: 'P0001', text: 'precondition_failed: challenge attempts exhausted', challenge: 'exhausted' },
  { code: 'P0001', text: 'precondition_failed: too many challenge requests', challenge: 'rate_limited' },
  { code: 'P0001', text: 'precondition_failed: too many registration attempts', challenge: 'rate_limited', registration: 'rate_limited' },
  { code: 'P0001', text: 'precondition_failed: no binding to challenge — register instead', challenge: 'register_instead' },
  { code: 'P0001', text: 'precondition_failed: the caller already owns this binding — register instead', challenge: 'register_instead' },
  { code: 'P0001', text: 'precondition_failed: binding no longer exists', challenge: 'register_instead' },
  { code: 'P0001', text: 'precondition_failed: token length', registration: 'precondition' },
  { code: 'P0001', text: 'precondition_failed: platform must be ios or android', registration: 'precondition' },
  { code: 'P0001', text: 'precondition_failed: device secret length', registration: 'precondition' },
];

describe('migration 135 still raises every text the client keys on', () => {
  for (const r of RAISED) {
    it(`raises '${r.text}' with errcode ${r.code}`, () => {
      // the exact raise, with the exact errcode, somewhere in the body
      const re = new RegExp(`raise exception '${r.text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}'[^;]*errcode = '${r.code}'`);
      expect(sql, `${MIGRATION} no longer raises "${r.text}" as ${r.code}`).toMatch(re);
      if (r.challenge) expect(classifyChallengeError({ code: r.code, message: r.text })).toBe(r.challenge);
      if (r.registration) expect(classifyRegistrationError({ code: r.code, message: r.text })).toBe(r.registration);
    });
  }
});

describe('migration 135 still returns every 200 literal the client branches on', () => {
  it('confirm outcomes: rebound (the only bind), nonce_mismatch + attempts_left, challenge_consumed, stale_nonce', () => {
    for (const o of ['rebound', 'nonce_mismatch', 'challenge_consumed', 'stale_nonce'] as const) {
      expect(sql, `no 'outcome', '${o}' in ${MIGRATION}`).toMatch(new RegExp(`'outcome',\\s*'${o}'`));
    }
    expect(sql).toMatch(/'attempts_left'/);
    expect(interpretConfirmReply({ outcome: 'rebound', token_id: 't' })).toEqual({ kind: 'rebound', tokenId: 't' });
    expect(interpretConfirmReply({ outcome: 'nonce_mismatch', attempts_left: 1 })).toEqual({ kind: 'nonce_mismatch', attemptsLeft: 1 });
    expect(interpretConfirmReply({ outcome: 'challenge_consumed' })).toEqual({ kind: 'consumed' });
    expect(interpretConfirmReply({ outcome: 'stale_nonce' })).toEqual({ kind: 'stale' });
  });

  it("challenge_required carries challenge {id, mode, expires_in_s} and is stamped contract_version 3", () => {
    expect(sql).toMatch(/'outcome',\s*'challenge_required'/);
    expect(sql).toMatch(/jsonb_build_object\('id'/);
    expect(sql).toMatch(/'expires_in_s'/);
    expect(sql).toMatch(/'contract_version',\s*3/);
  });
});
