/**
 * primary-checkout/payment-attempts.ts — fail-closed client for the draft
 * venue.payment_attempt RPCs. The RPCs are not deployable until the SQL draft
 * is registered/reviewed; when they are absent, every call throws and no PI
 * POST/client_secret follows.
 */
export type RpcCaller = (name: string, params: Record<string, unknown>) => PromiseLike<{
  data?: unknown;
  error?: { message?: string; code?: string } | null;
}>;

interface AttemptQuote {
  orderId: string;
  buyerId: string;
  sessionId: string;
  faceMinor: number;
  buyerFeeMinor: number;
  chargeMinor: number;
  currency: string;
}

export interface BeginAttemptInput extends AttemptQuote {
  attemptKey: string;
}

export interface AttachAttemptInput extends AttemptQuote {
  attemptId: string;
  piId: string;
}

export interface PaymentAttempt {
  attemptId: string;
  attemptKey: string;
  state: string;
  piId: string | null;
}

function fail(where: string, error: { message?: string; code?: string } | null | undefined): never {
  throw new Error(`${where} failed: ${error?.code ? `${error.code}: ` : ''}${error?.message ?? 'unknown error'}`);
}

const ATTEMPT_STATES = new Set(['creating', 'open', 'processing', 'succeeded', 'failed', 'canceled', 'unknown']);

function attemptShape(value: unknown, requestedKey: string): PaymentAttempt {
  const v = value as { attempt_id?: unknown; attempt_key?: unknown; state?: unknown; pi_id?: unknown } | null;
  if (!v || typeof v.attempt_id !== 'string' || !v.attempt_id
      || typeof v.attempt_key !== 'string' || v.attempt_key !== requestedKey
      || typeof v.state !== 'string' || !ATTEMPT_STATES.has(v.state)
      || !(v.pi_id === null || (typeof v.pi_id === 'string' && v.pi_id.trim().length > 0))) {
    throw new Error('begin_payment_attempt returned a malformed result');
  }
  if (v.state === 'creating' && v.pi_id !== null) throw new Error('creating attempt must not carry a PI');
  if (v.state !== 'creating' && v.pi_id === null) throw new Error('attached attempt must carry a PI');
  return { attemptId: v.attempt_id, attemptKey: v.attempt_key, state: v.state, piId: v.pi_id };
}

export async function beginPaymentAttempt(rpc: RpcCaller, input: BeginAttemptInput): Promise<PaymentAttempt> {
  if (!input.orderId || !input.attemptKey || !input.buyerId || !input.sessionId) {
    throw new Error('payment attempt identity incomplete');
  }
  if (!Number.isSafeInteger(input.faceMinor) || !Number.isSafeInteger(input.buyerFeeMinor)
      || !Number.isSafeInteger(input.chargeMinor) || input.chargeMinor !== input.faceMinor + input.buyerFeeMinor
      || input.currency !== 'USD') {
    throw new Error('payment attempt amounts/currency invalid');
  }
  const { data, error } = await rpc('begin_payment_attempt', {
    p_order_id: input.orderId,
    p_attempt_key: input.attemptKey,
    p_buyer_id: input.buyerId,
    p_session_id: input.sessionId,
    p_face_minor: input.faceMinor,
    p_buyer_fee_minor: input.buyerFeeMinor,
    p_charge_minor: input.chargeMinor,
    p_currency: input.currency,
  });
  if (error) fail('begin_payment_attempt', error);
  return attemptShape(data, input.attemptKey);
}

export async function attachPaymentAttempt(rpc: RpcCaller, input: AttachAttemptInput): Promise<void> {
  const { data, error } = await rpc('attach_payment_attempt', {
    p_attempt_id: input.attemptId,
    p_pi_id: input.piId,
    p_order_id: input.orderId,
    p_buyer_id: input.buyerId,
    p_session_id: input.sessionId,
    p_face_minor: input.faceMinor,
    p_buyer_fee_minor: input.buyerFeeMinor,
    p_charge_minor: input.chargeMinor,
    p_currency: input.currency,
  });
  if (error) fail('attach_payment_attempt', error);
  const v = data as { attempt_id?: unknown; state?: unknown; pi_id?: unknown } | null;
  if (!v || v.attempt_id !== input.attemptId || v.pi_id !== input.piId
      || typeof v.state !== 'string' || !v.state) {
    throw new Error('attach_payment_attempt returned a malformed result');
  }
  if (!new Set(['open', 'processing', 'succeeded']).has(v.state)) {
    throw new Error(`attach_payment_attempt refused state ${v.state}`);
  }
}

export async function markPaymentAttemptByPi(
  rpc: RpcCaller,
  piId: string,
  state: 'processing' | 'succeeded' | 'failed' | 'canceled' | 'unknown',
  stripeStatus: string,
): Promise<void> {
  const { data, error } = await rpc('mark_payment_attempt_by_pi', {
    p_pi_id: piId, p_state: state, p_stripe_status: stripeStatus,
  });
  if (error) fail('mark_payment_attempt_by_pi', error);
  const v = data as { attempt_id?: unknown; state?: unknown; pi_id?: unknown } | null;
  if (!v || typeof v.attempt_id !== 'string' || !v.attempt_id
      || v.state !== state || v.pi_id !== piId) {
    throw new Error('mark_payment_attempt_by_pi returned a malformed result');
  }
}

export interface ReplayBindingInput extends AttemptQuote {
  piId: string;
}

/** Service-only read of the persisted replay binding. No secret is returned. */
export async function requireReplayAttemptBinding(rpc: RpcCaller, input: ReplayBindingInput): Promise<void> {
  const { data, error } = await rpc('read_payment_attempt_binding', {
    p_order_id: input.orderId,
    p_pi_id: input.piId,
    p_buyer_id: input.buyerId,
    p_session_id: input.sessionId,
  });
  if (error) fail('read_payment_attempt_binding', error);
  const v = data as {
    attempt_id?: unknown; order_id?: unknown; buyer_id?: unknown; session_id?: unknown;
    pi_id?: unknown; state?: unknown; face_minor?: unknown; buyer_fee_minor?: unknown;
    amount_minor?: unknown; currency?: unknown;
  } | null;
  if (!v || typeof v.attempt_id !== 'string' || !v.attempt_id
      || v.order_id !== input.orderId || v.buyer_id !== input.buyerId
      || v.session_id !== input.sessionId || v.pi_id !== input.piId
      || !new Set(['open','processing','succeeded']).has(String(v.state))
      || v.face_minor !== input.faceMinor || v.buyer_fee_minor !== input.buyerFeeMinor
      || v.amount_minor !== input.chargeMinor || v.currency !== input.currency) {
    throw new Error('read_payment_attempt_binding returned a malformed/mismatched binding');
  }
}

export const STORED_CREATE_FIELDS = [
  'amount', 'currency', 'payment_method_types[0]', 'customer', 'setup_future_usage',
  'metadata[rail]', 'metadata[mode]', 'metadata[order_id]', 'metadata[buyer_id]',
  'metadata[org_id]', 'metadata[session_id]',
] as const;

export interface StoreCreateRequestInput extends BeginAttemptInput {
  attemptId: string;
  createRequest: Record<string, string>;
}

function assertStoreInput(input: StoreCreateRequestInput): void {
  if (!input.attemptId || !input.attemptKey || !input.orderId || !input.buyerId || !input.sessionId) {
    throw new Error('create-request identity is incomplete');
  }
  if (!Number.isSafeInteger(input.faceMinor) || input.faceMinor < 0
      || !Number.isSafeInteger(input.buyerFeeMinor) || input.buyerFeeMinor < 0
      || !Number.isSafeInteger(input.chargeMinor) || input.chargeMinor !== input.faceMinor + input.buyerFeeMinor
      || input.currency !== 'USD') {
    throw new Error('create-request quote is invalid');
  }
}

function validateCreateRequest(request: Record<string, string>, input: BeginAttemptInput): void {
  const keys = Object.keys(request).sort();
  const allowed = [...STORED_CREATE_FIELDS].sort();
  if (keys.length !== allowed.length || keys.some((k, i) => k !== allowed[i])) {
    throw new Error('create request has unsupported/extra fields');
  }
  if (Object.values(request).some((v) => typeof v !== 'string')) {
    throw new Error('create request values must be strings');
  }
  if (!/^\d+$/.test(request['amount']) || request['amount'] !== String(input.chargeMinor)) {
    throw new Error('create request amount must equal the persisted charge');
  }
  if (request['currency'] !== 'usd' || request['payment_method_types[0]'] !== 'card'
      || request['setup_future_usage'] !== 'on_session'
      || request['metadata[rail]'] !== 'native_primary'
      || request['metadata[mode]'] !== 'native_primary'
      || request['metadata[order_id]'] !== input.orderId
      || request['metadata[buyer_id]'] !== input.buyerId
      || request['metadata[session_id]'] !== input.sessionId) {
    throw new Error('create request identity/contract mismatch');
  }
  if (!request['customer'] || request['customer'].trim() === '') {
    throw new Error('create request customer is required');
  }
  if (!request['metadata[org_id]'] || request['metadata[org_id]'].trim() === '') {
    throw new Error('create request org_id is required');
  }
}

export async function storePaymentAttemptRequest(rpc: RpcCaller, input: StoreCreateRequestInput): Promise<void> {
  assertStoreInput(input);
  validateCreateRequest(input.createRequest, input);
  if (Object.keys(input.createRequest).some((k) => /secret|token|client_secret/i.test(k))) {
    throw new Error('create request contains a secret-like field');
  }
  const { data, error } = await rpc('store_payment_attempt_request', {
    p_attempt_id: input.attemptId,
    p_order_id: input.orderId,
    p_buyer_id: input.buyerId,
    p_session_id: input.sessionId,
    p_create_request: input.createRequest,
  });
  if (error) fail('store_payment_attempt_request', error);
  const v = data as {
    attempt_id?: unknown; order_id?: unknown; buyer_id?: unknown; session_id?: unknown;
    pi_id?: unknown; state?: unknown; face_minor?: unknown; buyer_fee_minor?: unknown;
    amount_minor?: unknown; currency?: unknown; create_request?: unknown;
  } | null;
  if (!v || v.attempt_id !== input.attemptId || v.order_id !== input.orderId
      || v.buyer_id !== input.buyerId || v.session_id !== input.sessionId
      || v.face_minor !== input.faceMinor || v.buyer_fee_minor !== input.buyerFeeMinor
      || v.amount_minor !== input.chargeMinor || v.currency !== input.currency
      || (v.state !== 'creating' && v.state !== 'open')
      || (v.state === 'creating' && v.pi_id !== null)
      || (v.state === 'open' && (typeof v.pi_id !== 'string' || v.pi_id.trim() === ''))
      || !v.create_request || typeof v.create_request !== 'object'
      || STORED_CREATE_FIELDS.some((k) => (v.create_request as Record<string, unknown>)[k] !== input.createRequest[k])
      || Object.keys(v.create_request as Record<string, unknown>).length !== STORED_CREATE_FIELDS.length) {
    throw new Error('store_payment_attempt_request returned a malformed/mismatched result');
  }
}

export interface RecoveredPaymentAttempt {
  attemptId: string;
  attemptKey: string;
  orderId: string;
  buyerId: string;
  sessionId: string;
  piId: string | null;
  state: 'creating' | 'open';
  faceMinor: number;
  buyerFeeMinor: number;
  chargeMinor: number;
  currency: string;
  createRequest: Record<string, string>;
}

export async function readPaymentAttemptRecovery(
  rpc: RpcCaller,
  input: { orderId: string; buyerId: string; sessionId: string },
): Promise<RecoveredPaymentAttempt> {
  if (!input.orderId || !input.buyerId || !input.sessionId) throw new Error('recovery identity incomplete');
  const { data, error } = await rpc('read_payment_attempt_recovery', {
    p_order_id: input.orderId, p_buyer_id: input.buyerId, p_session_id: input.sessionId,
  });
  if (error) fail('read_payment_attempt_recovery', error);
  const v = data as Record<string, unknown> | null;
  if (!v || typeof v.attempt_id !== 'string' || !v.attempt_id
      || typeof v.attempt_key !== 'string' || !v.attempt_key.trim() || v.attempt_key.length > 200
      || v.order_id !== input.orderId || v.buyer_id !== input.buyerId || v.session_id !== input.sessionId
      || !Number.isSafeInteger(v.face_minor) || (v.face_minor as number) < 0
      || !Number.isSafeInteger(v.buyer_fee_minor) || (v.buyer_fee_minor as number) < 0
      || !Number.isSafeInteger(v.amount_minor) || (v.amount_minor as number) !== (v.face_minor as number) + (v.buyer_fee_minor as number)
      || v.currency !== 'USD'
      || (v.state !== 'creating' && v.state !== 'open')
      || (v.state === 'creating' && v.pi_id !== null)
      || (v.state === 'open' && (typeof v.pi_id !== 'string' || v.pi_id.trim() === ''))
      || !v.create_request || typeof v.create_request !== 'object' || Array.isArray(v.create_request)) {
    throw new Error('read_payment_attempt_recovery returned a malformed/mismatched result');
  }
  const request = v.create_request as Record<string, string>;
  validateCreateRequest(request, {
    orderId: input.orderId, buyerId: input.buyerId, sessionId: input.sessionId,
    faceMinor: v.face_minor as number, buyerFeeMinor: v.buyer_fee_minor as number,
    chargeMinor: v.amount_minor as number, currency: v.currency as string,
    attemptKey: v.attempt_key as string,
  });
  return {
    attemptId: v.attempt_id, attemptKey: v.attempt_key,
    orderId: input.orderId, buyerId: input.buyerId, sessionId: input.sessionId,
    piId: v.pi_id as string | null, state: v.state as 'creating'|'open',
    faceMinor: v.face_minor as number, buyerFeeMinor: v.buyer_fee_minor as number,
    chargeMinor: v.amount_minor as number, currency: v.currency as string,
    createRequest: request,
  };
}
