import { describe, expect, it } from 'vitest';
import { STORED_CREATE_FIELDS, storePaymentAttemptRequest, type RpcCaller } from '../supabase/functions/primary-checkout/payment-attempts';

const ORDER = 'aaaa0001-bbbb-4ccc-8ddd-eeee00000001';
const ATTEMPT = 'att_1';
const BUYER = 'buyer-1';
const SESSION = 'a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d';
const request = Object.fromEntries(STORED_CREATE_FIELDS.map((k) => [k, 'x'])) as Record<string, string>;
Object.assign(request, {
  amount: '2800', currency: 'usd', 'payment_method_types[0]': 'card', customer: 'cus_1',
  setup_future_usage: 'on_session', 'metadata[rail]': 'native_primary', 'metadata[mode]': 'native_primary',
  'metadata[order_id]': ORDER, 'metadata[buyer_id]': BUYER, 'metadata[org_id]': 'org-1', 'metadata[session_id]': SESSION,
});
const input = { attemptId: ATTEMPT, orderId: ORDER, buyerId: BUYER, sessionId: SESSION,
  faceMinor: 2500, buyerFeeMinor: 300, chargeMinor: 2800, currency: 'USD', attemptKey: 'key', createRequest: request };
const reply = (over: Record<string, unknown> = {}): RpcCaller => async (name, params) => ({
  data: { attempt_id: params.p_attempt_id, order_id: params.p_order_id, buyer_id: params.p_buyer_id,
    session_id: params.p_session_id, pi_id: null, state: 'creating',
    face_minor: 2500, buyer_fee_minor: 300, amount_minor: 2800, currency: 'USD',
    create_request: params.p_create_request, ...over },
});
const expectFail = async (fn: () => Promise<void>) => { await expect(fn()).rejects.toThrow(); };

describe('persisted create request helper', () => {
  it('accepts the exact supported request and exact retry', async () => {
    await expect(storePaymentAttemptRequest(reply(), input)).resolves.toBeUndefined();
    await expect(storePaymentAttemptRequest(reply(), input)).resolves.toBeUndefined();
  });
  it('rejects missing RPC, malformed/foreign records, changed body, extra fields and secrets', async () => {
    await expectFail(() => storePaymentAttemptRequest(async () => ({ error: { message: 'missing RPC' } }), input));
    await expectFail(() => storePaymentAttemptRequest(async () => ({ data: null }), input));
    await expectFail(() => storePaymentAttemptRequest(reply({ attempt_id: 'other' }), input));
    await expectFail(() => storePaymentAttemptRequest(reply({ buyer_id: 'other' }), input));
    await expectFail(() => storePaymentAttemptRequest(reply({ create_request: { ...request, amount: '9999' } }), input));
    await expectFail(() => storePaymentAttemptRequest(reply(), { ...input, createRequest: { ...request, extra: 'x' } }));
    await expectFail(() => storePaymentAttemptRequest(reply(), { ...input, createRequest: { ...request, client_secret: 'x' } }));
  });

  it('rejects invalid states/PI pairs and returned quote mismatches', async () => {
    for (const patch of [{ state: 'canceled' }, { state: 'creating', pi_id: 'pi_foreign' }, { state: 'open', pi_id: null }, { state: 'open', pi_id: '' }, { face_minor: 1 }, { buyer_fee_minor: 1 }, { amount_minor: 1 }, { currency: 'EUR' }]) {
      await expectFail(() => storePaymentAttemptRequest(reply(patch), input));
    }
    await expect(storePaymentAttemptRequest(reply({ state: 'open', pi_id: 'pi_ok' }), input)).resolves.toBeUndefined();
    await expect(storePaymentAttemptRequest(reply({ state: 'open', pi_id: 'pi_ok' }), input)).resolves.toBeUndefined();
  });

  it('rejects direct bad amount, customer whitespace and metadata/identity mismatch', async () => {
    for (const r of [
      { ...request, amount: '9999' },
      { ...request, customer: '   ' },
      { ...request, 'metadata[org_id]': '   ' },
      { ...request, 'metadata[order_id]': 'foreign' },
      { ...request, 'metadata[session_id]': 'foreign' },
      { ...request, 'metadata[buyer_id]': 'foreign' },
    ]) {
      await expectFail(() => storePaymentAttemptRequest(reply(), { ...input, createRequest: r }));
    }
    await expectFail(() => storePaymentAttemptRequest(reply(), { ...input, attemptId: '' }));
  });
});

import { readPaymentAttemptRecovery } from '../supabase/functions/primary-checkout/payment-attempts';

describe('recovery read helper', () => {
  const rec = (over: Record<string, unknown> = {}) => ({
    attempt_id: ATTEMPT, attempt_key: 'key', order_id: ORDER, buyer_id: BUYER, session_id: SESSION,
    pi_id: null, state: 'creating', face_minor: 2500, buyer_fee_minor: 300, amount_minor: 2800,
    currency: 'USD', create_request: request, ...over,
  });
  const rpc = (over: Record<string, unknown> = {}): RpcCaller => async () => ({ data: rec(over) });
  const input = { orderId: ORDER, buyerId: BUYER, sessionId: SESSION };
  it('accepts exact creating and open recovery records', async () => {
    await expect(readPaymentAttemptRecovery(rpc(), input)).resolves.toMatchObject({ state: 'creating', piId: null });
    await expect(readPaymentAttemptRecovery(rpc({ state: 'open', pi_id: 'pi_ok' }), input)).resolves.toMatchObject({ state: 'open', piId: 'pi_ok' });
  });
  it('rejects missing RPC/null/error and every invalid state/PI pair', async () => {
    await expect(readPaymentAttemptRecovery(async () => ({ error: { message: 'missing' } }), input)).rejects.toThrow();
    await expect(readPaymentAttemptRecovery(async () => ({ data: null }), input)).rejects.toThrow();
    for (const patch of [{ state: 'failed' }, { state: 'unknown' }, { state: 'processing' }, { state: 'succeeded' }, { state: 'canceled' }, { pi_id: 'pi_foreign' }, { state: 'open', pi_id: null }, { state: 'open', pi_id: '' }]) {
      await expect(readPaymentAttemptRecovery(rpc(patch), input)).rejects.toThrow();
    }
  });
  it('rejects identity/quote/request/key mismatch', async () => {
    for (const patch of [
      { order_id: 'foreign' }, { buyer_id: 'foreign' }, { session_id: 'foreign' },
      { face_minor: 1 }, { buyer_fee_minor: 1 }, { amount_minor: 1 }, { currency: 'EUR' },
      { attempt_key: '' }, { attempt_key: 'x'.repeat(201) },
      { create_request: { ...request, amount: '9999' } },
      { create_request: { ...request, customer: '   ' } },
      { create_request: { ...request, 'metadata[org_id]': '   ' } },
      { create_request: { ...request, 'metadata[order_id]': 'foreign' } },
      { create_request: { ...request, extra: 'x' } },
    ]) await expect(readPaymentAttemptRecovery(rpc(patch), input)).rejects.toThrow();
  });
});
