/**
 * tests/helpers/payouts-vm.ts — load the REAL supabase/functions/_shared/payouts.ts
 * into vitest.
 *
 * payouts.ts imports ./stripe.ts, which reads Deno.env at module load, so
 * vitest cannot import it directly. Same trick as edge-vm.ts: strip the
 * import statements, transpile to CommonJS, evaluate in a vm whose globals
 * bind exactly the names the imports would have bound — the mocked Stripe
 * transport from mockStripe() and the REAL payout-logic module.
 */
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import vm from 'node:vm';
import ts from 'typescript';

import * as payoutLogic from '../../supabase/functions/_shared/payout-logic';
import { REPO_ROOT } from './edge-vm';

const IMPORT_RE = /^import[\s\S]*?from\s+['"][^'"]+['"];[ \t]*$/gm;

// The public contract of _shared/payouts.ts, restated here because the module
// itself cannot enter the tsc program (Deno `.ts` imports). Keep in sync.
export type PayoutAttemptOutcome =
  | { kind: 'succeeded';         attemptId: string; attemptNo: number; stripeTransferId: string; destination: string; sellerNetCents: number; sourceChargeId: string }
  | { kind: 'reversal_required'; attemptId: string; attemptNo: number; stripeTransferId: string; destination: string; sellerNetCents: number }
  | { kind: 'already_released' }
  | { kind: 'in_progress' }
  | { kind: 'reconciled';        attemptId: string; state: string; stripeTransferId: string | null; found: boolean }
  | { kind: 'reconcile_pending'; attemptId: string; error: string; unmatched: string[] }
  | { kind: 'not_eligible';      reason: string }
  | { kind: 'deferred';          attemptId: string; reasonCode: string; evidence: Record<string, unknown>; page: boolean; error?: string }
  | { kind: 'unknown';           attemptId: string; error: string }
  | { kind: 'db_error';          stage: 'claim' | 'mark' | 'record' | 'reconcile'; error: string; attemptId?: string; stripeTransferId?: string };

export interface PayoutDb {
  rpc(name: string, params: Record<string, unknown>): PromiseLike<{ data: unknown; error: { message: string } | null }>;
}

export interface SellerPayoutArgs {
  transferId: string; paymentId: string; sellerId: string; attemptId: string; attemptNo: number;
  idempotencyKey: string; destination: string; paymentIntentId: string; sellerNetCents: number; sourceChargeId?: string | null;
}

export interface Payouts {
  executePayoutAttempt(db: PayoutDb, args: { transferId: string; paymentId: string; sellerId: string; actor: string }): Promise<PayoutAttemptOutcome>;
  createSellerPayout(args: SellerPayoutArgs, hooks?: { beforeTransfer?: () => Promise<boolean> }): Promise<{ ok: boolean; [k: string]: unknown }>;
  findTransferByAttempt(transferId: string, attemptId: string): Promise<{ ok: boolean; transfer?: { id: string } | null; unmatched?: string[]; error?: string }>;
}

export function loadPayoutsModule(stripe: {
  stripeFetchRaw: (...args: never[]) => Promise<{ ok: boolean; status: number; data: unknown }>;
  stripeFetch?: (...args: never[]) => Promise<unknown>;
}): Payouts {
  const abs = resolve(REPO_ROOT, 'supabase/functions/_shared/payouts.ts');
  const source = readFileSync(abs, 'utf8').replace(IMPORT_RE, '');
  const js = ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS },
    fileName: abs,
  }).outputText;
  const module = { exports: {} as Record<string, unknown> };
  const ctx: Record<string, unknown> = {
    ...payoutLogic,
    stripeFetchRaw: stripe.stripeFetchRaw,
    stripeFetch: stripe.stripeFetch ?? (async () => { throw new Error('stripeFetch not provided'); }),
    module, exports: module.exports,
    console, Promise, Error, Array, Object, String, Number, Boolean, JSON, Math,
    encodeURIComponent, decodeURIComponent,
  };
  vm.runInNewContext(js, ctx, { filename: abs });
  return module.exports as unknown as Payouts;
}
