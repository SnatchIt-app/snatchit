#!/usr/bin/env node
/**
 * scripts/ci/assert-env-pairing.mjs — build-time twin of src/config/envGuard.ts.
 *
 * Every eas.json build profile must pair a Supabase project with a Stripe
 * account that belongs to it. This catches the dangerous combinations BEFORE a
 * binary exists, because EXPO_PUBLIC_* values are inlined at bundle time and
 * cannot be corrected afterwards.
 *
 * Exit 1 on any violation. Run in CI and before any build.
 */
import { readFileSync } from 'node:fs';

const SANDBOX_REF = 'ofaidukbieeekqaboscm';
const PROD_REF = 'hqycwntpfoztoinemqns';
const SANDBOX_ACCT = '51T6Fb1';
const LIVE_ACCT = '51T6Far';

/**
 * Tolerated violations. EMPTY, and it must stay empty.
 *
 * It held two entries until 2026-09-07: `development` and `preview` paired the
 * LIVE account's TEST publishable key with the PRODUCTION Supabase project, so a
 * build from either read and wrote production data while payments could not work
 * (runtime guard F4 refused to run them). Both profiles now target the sandbox
 * pair — sandbox Supabase project + sandbox Stripe account — so the entries were
 * removed rather than carried. Never add a profile here to make this check pass:
 * fix the pairing instead. A profile that legitimately cannot be paired yet
 * leaves its client identifiers empty (see the note branch below).
 */
const KNOWN_VIOLATIONS = new Set([]);

const eas = JSON.parse(readFileSync(new URL('../../eas.json', import.meta.url), 'utf8'));
const problems = [];
const notes = [];

for (const [name, profile] of Object.entries(eas.build ?? {})) {
  const env = profile.env ?? {};
  const url = env.EXPO_PUBLIC_SUPABASE_URL ?? '';
  const pk = env.EXPO_PUBLIC_STRIPE_PUBLISHABLE_KEY ?? '';
  const anon = env.EXPO_PUBLIC_SUPABASE_ANON_KEY ?? '';
  const appEnv = env.EXPO_PUBLIC_APP_ENV ?? '';
  const host = url.replace(/^https?:\/\//, '').split('/')[0];
  const ref = host.endsWith('.supabase.co') ? host.slice(0, -'.supabase.co'.length) : '';
  const isTest = pk.startsWith('pk_test_');
  const isLive = pk.startsWith('pk_live_');
  const acct = pk.replace(/^pk_(test|live)_/, '').slice(0, 7);
  const at = (code, msg) => problems.push(`${name}: ${code} ${msg}`);

  // A profile may deliberately leave client identifiers empty (they are then
  // supplied locally and never committed); such a profile cannot be built by
  // EAS, which is the point, so only pairing of PRESENT values is asserted.
  if (!pk && !anon) {
    notes.push(`${name}: client identifiers intentionally empty (supplied locally, never committed)`);
  }
  if (ref && ref !== SANDBOX_REF && ref !== PROD_REF) at('F7', `unknown Supabase ref ${ref}`);
  if (ref === PROD_REF && isTest) at('F4', 'TEST Stripe key paired with the PRODUCTION project');
  if (ref === SANDBOX_REF && isLive) at('F3', 'LIVE Stripe key paired with the SANDBOX project');
  if (pk && ref === SANDBOX_REF && acct !== SANDBOX_ACCT) at('F5', 'Stripe key is not the sandbox account');
  if (pk && ref === PROD_REF && acct !== LIVE_ACCT) at('F5', 'Stripe key is not the production account');
  if (appEnv === 'sandbox' && ref !== SANDBOX_REF) at('F1', 'APP_ENV=sandbox but not the sandbox project');
  if (appEnv === 'production' && !(ref === PROD_REF && isLive)) at('F2', 'APP_ENV=production but not production+live');
  // The anon key, when it is a legacy JWT, embeds its own project ref.
  if (anon.startsWith('eyJ')) {
    try {
      const claims = JSON.parse(Buffer.from(anon.split('.')[1], 'base64').toString('utf8'));
      if (ref && claims.ref && claims.ref !== ref) at('F9', `anon key belongs to ${claims.ref}, not ${ref}`);
    } catch {
      at('F9', 'anon key looks like a JWT but could not be decoded');
    }
  }
}

for (const n of notes) console.log(`note  ${n}`);
const known = problems.filter((p) => KNOWN_VIOLATIONS.has(p));
const unknown = problems.filter((p) => !KNOWN_VIOLATIONS.has(p));
for (const k of known) {
  console.log(`KNOWN (tracked, profile unusable until repointed): ${k}`);
}
const stale = [...KNOWN_VIOLATIONS].filter((k) => !problems.includes(k));
for (const s of stale) console.log(`resolved — remove from KNOWN_VIOLATIONS: ${s}`);
problems.length = 0;
problems.push(...unknown);
if (problems.length) {
  console.error('\nenv pairing check FAILED:');
  for (const p of problems) console.error(`  ✗ ${p}`);
  console.error('\nA build profile must never pair one environment\'s database with another\'s Stripe account.');
  process.exit(1);
}
console.log(`env pairing check OK (${Object.keys(eas.build ?? {}).length} profiles)`);
