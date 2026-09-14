/**
 * tests/premium-pending-states.test.ts — batch 2 pending states on the money paths.
 *
 * CFT-203 (visible pending labels), CFT-205 (single-flight locks), CFT-202
 * (success haptic only after authoritative confirmation) on Buy Now, transfer
 * receive, the delivery form and the checkout pay control. Source contracts:
 * these screens cannot render under vitest.
 */

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const root = resolve(__dirname, '..');
const read = (rel: string) => readFileSync(resolve(root, rel), 'utf8');
const stripComments = (s: string) =>
  s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

describe('Listing detail — Buy Now', () => {
  const screen = read('src/screens/ListingDetailScreen.tsx');
  const code = stripComments(screen);

  it('holds a single-flight lock around the reserve call and shows "Reserving…"', () => {
    expect(screen).toContain('const buyFlight = useSingleFlight();');
    expect(screen).toContain('await buyFlight.run(reserveAndCheckout)');
    expect(screen).toContain('pendingLabel="Reserving…"');
  });

  it('the reserve path is unchanged inside the lock', () => {
    const start = code.indexOf('async function reserveAndCheckout()');
    const body = code.slice(start, code.indexOf('// ── Transfer actions', start) > 0 ? code.indexOf('// ── Transfer actions', start) : start + 4000);
    for (const marker of ["rpc('reserve_buy_now'", 'await fetchData();', 'navigateToCheckout();', 'setReserving(false);']) {
      expect(body, marker).toContain(marker);
    }
  });
});

describe('Transfer receive — confirm and report', () => {
  const screen = read('app/transfer/receive/[id].tsx');
  const code = stripComments(screen);

  it('confirm and report are separate pending states on one lock', () => {
    expect(screen).toContain('const [confirming, setConfirming] = useState(false);');
    expect(screen).toContain('const [disputing, setDisputing] = useState(false);');
    expect(screen).toContain('const busy = confirming || disputing;');
    expect(screen).toContain('flight.run(confirmReceipt)');
    expect(code).toMatch(/onPress: \(\) => \{\s*flight\.run\(async \(\) => \{\s*setDisputing\(true\);/);
    expect(code).not.toContain('setSubmitting(');
  });

  it('each button shows its own pending label and both disable while either runs', () => {
    expect(screen).toContain('pendingLabel="Confirming receipt…"');
    expect(screen).toContain('pendingLabel="Reporting…"');
    expect(code).toMatch(/loading=\{confirming\}\s*disabled=\{busy\}/);
    expect(code).toMatch(/loading=\{disputing\}\s*disabled=\{busy\}/);
  });

  it('the success haptic fires only after confirm-and-release succeeded', () => {
    const invoke = code.indexOf("functions.invoke('confirm-and-release'");
    const errorReturn = code.indexOf("Alert.alert('Error', message);");
    const haptic = code.indexOf('hapticSuccess();');
    const confirmed = code.indexOf("status: 'buyer_confirmed'");
    expect(invoke).toBeGreaterThan(0);
    expect(errorReturn).toBeGreaterThan(invoke);
    expect(haptic).toBeGreaterThan(errorReturn);
    expect(confirmed).toBeGreaterThan(haptic);
    // exactly one success haptic on this screen, none on the dispute path
    expect(code.split('hapticSuccess();').length - 1).toBe(1);
  });

  it('the transfer path is otherwise unchanged', () => {
    for (const marker of ["rpc('mark_transfer_viewed'", "rpc('set_transfer_delivery_info'", "rpc('buyer_dispute_transfer'", 'KeyboardAvoidingView']) {
      expect(screen).toContain(marker);
    }
  });
});

describe('Delivery form — the shared Button', () => {
  const form = read('src/components/DeliveryInfoForm.tsx');
  it('submits through Button with a visible "Saving…" and keeps its accessible name', () => {
    expect(form).toContain("import { Button } from '@/src/components/ui';");
    expect(form).toContain('pendingLabel="Saving…"');
    expect(form).toContain('accessibilityLabel="Save delivery info"');
    expect(stripComments(form)).not.toMatch(/<Pressable\b|ActivityIndicator/);
  });
});

describe('Checkout — pay control and completion (display only; for A)', () => {
  const screen = read('src/screens/checkout/CheckoutNative.tsx');
  const code = stripComments(screen);

  it('the pending states payControl names are visible beside the spinner', () => {
    expect(screen).toContain('pendingLabel={pay.loading ? pay.label : undefined}');
  });

  it('one success haptic, keyed on the completed outcome only', () => {
    expect(screen).toContain('useEffect(() => { if (completed) hapticSuccess(); }, [completed]);');
    expect(code.split('hapticSuccess').length - 1).toBe(2); // import + the one call
  });

  it('the hold countdown uses tabular digits (CFT-207)', () => {
    expect(code).toMatch(/hold: \{[^}]*fontVariant: \['tabular-nums'\]/);
  });

  it('nothing in the pay decision or handlers changed', () => {
    for (const marker of [
      'const pay = payControl({',
      "pay.action === 'pay' ? payHandler",
      "pay.action === 'retry' ? () => setupPaymentRef.current?.()",
      "pay.action === 'back' ? () => router.back()",
    ]) {
      expect(screen).toContain(marker);
    }
  });
});
