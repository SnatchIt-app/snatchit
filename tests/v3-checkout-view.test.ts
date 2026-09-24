/**
 * tests/v3-checkout-view.test.ts — checkout's presentation, and the property that makes it
 * renderable at all.
 *
 * THE OWNER'S INSTRUCTION (2026-09-24): "Complete checkout presentation through a rendering path
 * that cannot mount payment setup." Every other V3 surface is compared against its board as the app
 * renders it. Checkout could not join that, for two independent reasons:
 *
 *  1. mounting the real screen signed in RUNS the setup effect, and `decideCheckoutSetup` step 3
 *     calls `createIntent()` for auction mode — so opening it creates or reuses a PaymentIntent;
 *  2. `CheckoutNative.tsx` imports `@stripe/stripe-react-native`, which reaches
 *     `TurboModuleRegistry`. The platform split (`CheckoutEntry.tsx` vs `.native.tsx`) exists to
 *     keep that out of the web bundle, and weakening it to take a screenshot would trade a shipping
 *     safeguard for a picture.
 *
 * So the presentation lives in `CheckoutView.tsx` and the effects stay in `CheckoutNative.tsx`. The
 * first test below is the one that matters: it walks the view's TRANSITIVE import graph and proves
 * no native payment module, no supabase client and no payment/setup function is reachable from it.
 * A harness that mounts the view cannot create an intent — not because it chooses not to, but
 * because nothing it can reach is able to.
 *
 * Every other case here pins what the V3 boards require of the rendering (pkg8-checkout-dark /
 * pkg8-checkout-light): the screen-title voice with a chip back control, the 52pt full-width pay
 * pill, and the states drawn in the V3 quote treatment rather than as loose paragraphs.
 */
import { describe, expect, it } from 'vitest';
import { readFileSync, existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';

const ROOT = resolve(__dirname, '..');
const VIEW = 'src/screens/checkout/CheckoutView.tsx';

const read = (rel: string) => readFileSync(join(ROOT, rel), 'utf8');
const code = (rel: string) => read(rel).replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

/**
 * The RUNTIME import specifiers in a file: comments stripped so a mention in prose is not an import,
 * and `import type` statements skipped because a type is erased at build and can execute nothing.
 */
function imports(rel: string): string[] {
  const src = code(rel).replace(/import\s+type\s+[^;]*?;/g, '');
  return [...src.matchAll(/from\s+'([^']+)'|require\('([^']+)'\)/g)].map((m) => m[1] ?? m[2]);
}

/** Resolve a specifier to a repo-relative file, or null for a package / an unresolvable asset. */
function resolveLocal(spec: string, fromRel: string): string | null {
  let base: string;
  if (spec.startsWith('@/')) base = join(ROOT, spec.slice(2));
  else if (spec.startsWith('.')) base = resolve(ROOT, dirname(fromRel), spec);
  else return null;                                   // a package: recorded, not walked
  for (const ext of ['.ts', '.tsx', '.native.tsx', '.native.ts', '/index.ts', '/index.tsx']) {
    if (existsSync(base + ext)) return (base + ext).slice(ROOT.length + 1);
  }
  return existsSync(base) ? base.slice(ROOT.length + 1) : null;
}

/** Everything reachable from `entry`: the local files, the packages, and one path to each file. */
function graph(entry: string): { files: Set<string>; packages: Set<string>; pathTo: Map<string, string[]> } {
  const files = new Set<string>();
  const packages = new Set<string>();
  const pathTo = new Map<string, string[]>([[entry, [entry]]]);
  const queue = [entry];
  while (queue.length) {
    const rel = queue.shift()!;
    if (files.has(rel)) continue;
    files.add(rel);
    for (const spec of imports(rel)) {
      const local = resolveLocal(spec, rel);
      if (local) {
        if (!pathTo.has(local)) pathTo.set(local, [...pathTo.get(rel)!, local]);
        queue.push(local);
      } else if (!spec.startsWith('.') && !spec.startsWith('@/')) {
        packages.add(spec.split('/').slice(0, spec.startsWith('@') ? 2 : 1).join('/'));
      }
    }
  }
  return { files, packages, pathTo };
}

describe('the rendering path cannot mount payment setup', () => {
  it('CV1 (witness): the graph walker actually walks, and the screen it is contrasted with DOES reach the payment module', () => {
    // Without this, every absence below could be the walker returning nothing.
    const screen = graph('src/screens/checkout/CheckoutNative.tsx');
    expect(screen.files.size).toBeGreaterThan(10);
    expect(screen.packages).toContain('@stripe/stripe-react-native');
    expect([...screen.files]).toContain('src/lib/checkout/setupDecision.ts');
    expect([...screen.files]).toContain('src/lib/supabase.ts');
    // And the view's own graph is non-trivial, so its absences are absences.
    const view = graph(VIEW);
    expect(view.files.size).toBeGreaterThan(5);
    expect([...view.files]).toContain('src/components/checkout/OrderIdentity.tsx');
  });

  it('CV2: no native payment module, and no Stripe package at all, is reachable from the view', () => {
    const { packages } = graph(VIEW);
    for (const pkg of [...packages]) {
      expect(pkg.startsWith('@stripe/'), `reachable package ${pkg}`).toBe(false);
    }
  });

  it('CV3: no setup, intent, sheet or settlement FUNCTION is reachable from the view', () => {
    const { files } = graph(VIEW);
    // The modules that can move money or decide whether to: none of them is in the graph.
    for (const forbidden of [
      'src/lib/checkout/setupDecision.ts',
      'src/lib/checkout/settledRead.ts',
      'src/lib/checkout/payControl.ts',
      'src/lib/checkout/paymentGuard.ts',
      'src/lib/payments.ts',
    ]) {
      expect([...files], `${forbidden} must not be reachable`).not.toContain(forbidden);
    }
    // The payment module appears in the view exactly once, as an erased TYPE. The settlement words
    // arrive as a prop from the screen, which reads the same table the alert does.
    expect(code(VIEW)).toContain("import type { SettlementOutcome } from '@/src/lib/payments';");
    expect(code(VIEW).match(/from '@\/src\/lib\/payments'/g)?.length).toBe(1);
    expect(code('src/screens/checkout/CheckoutNative.tsx')).toContain('copy={SETTLEMENT_COPY[settlement]}');
    for (const fn of ['createPaymentIntent', 'finalizePurchase', 'confirmPaymentSuccess', 'reconcilePriceChange']) {
      expect(code(VIEW), fn).not.toContain(fn);
    }
  });

  it('CV3b: the supabase client is reachable ONLY through the shared primitives barrel, and the view names nothing on it', () => {
    /*
     * Stated precisely, because a vague claim here would be the useful kind of lie. The client IS in
     * the graph, by exactly one route: `src/components/ui/index.ts` re-exports MediaUpload, whose
     * upload hook imports it. Every screen in the app reaches it that way, it cannot create or
     * confirm a PaymentIntent, and the view neither imports MediaUpload nor names a client symbol.
     * The route is recorded here so a future path — a real read creeping into the presentation —
     * fails this test instead of hiding behind "supabase was always reachable".
     */
    const { pathTo } = graph(VIEW);
    expect(pathTo.get('src/lib/supabase.ts')).toEqual([
      VIEW,
      'src/components/ui/index.ts',
      'src/components/ui/MediaUpload.tsx',
      'src/hooks/useImageUpload.ts',
      'src/lib/supabase.ts',
    ]);
    const src = code(VIEW);
    expect(src).not.toMatch(/MediaUpload|supabase|createClient/);
  });

  it('CV4: the view holds no effect that reads anything, and no handler of its own', () => {
    const src = code(VIEW);
    // Its only effect is the one-per-purchase success haptic, which touches no server.
    expect(src.match(/useEffect\(/g)?.length).toBe(1);
    expect(src).toContain('hapticSuccess()');
    expect(src).not.toMatch(/\bfetch\(|\.rpc\(|functions\.invoke|supabase/);
    // Navigation is the one side effect it performs, and only to the two destinations the terminal
    // faces already owned.
    expect(src.match(/router\.replace\(/g)?.length).toBe(3);
    expect(src).not.toContain('router.push');
  });
});

describe('the V3 rendering the boards ask for (pkg8-checkout-dark / -light)', () => {
  const src = code(VIEW);

  it('CV5: the header is the screen-title voice with a chip back control — the order screen\'s header', () => {
    expect(src).toMatch(/<IconButton glyph="back" chip accessibilityLabel="Go back"/);
    expect(src).toMatch(/textStyle\('screenTitle'\)/);
    expect(src).not.toMatch(/textStyle\('displaySm'\)/);   // the V2 voice this replaces
    expect(src).toContain("export const CHECKOUT_TITLE = 'Checkout';");
  });

  it('CV6: the pay control is the 52pt full-width pill, and it is the only action in the bar', () => {
    const bar = src.slice(src.indexOf('<View style={[s.bar'), src.indexOf('</View>', src.indexOf('<View style={[s.bar')));
    expect(bar.match(/size="lg"/g)?.length).toBe(2);       // the pay control and the accept-total control
    expect(bar.match(/block/g)?.length).toBe(2);
    expect(bar).not.toMatch(/size="md"/);
    // Two controls in source, never both at once: the accept-total control REPLACES the pay control.
    expect(bar).toMatch(/\{acceptTotal \? \([\s\S]*?\) : \(/);
  });

  it('CV7: a state with a title is drawn in the V3 quote treatment, not as loose paragraphs', () => {
    expect(src).toMatch(/notice: \{[\s\S]*?borderRadius: v2\.radius\.md,\s*borderLeftWidth: 3,/);
    expect(src).toContain('borderLeftColor: palette.status.warning');
    // It keeps the live region that announced these states before.
    expect(src).toMatch(/accessibilityLiveRegion="polite"/);
    // And the one state that offers an action gets a real Button, not a tappable line of text.
    expect(src).toMatch(/notice\.action \?[\s\S]*?<Button/);
  });

  it("CV9: the fixture set's coverage is checked where the fixtures can be RESOLVED, not read as text", () => {
    /*
     * This case used to assert that each payControl label appeared somewhere in the harness FILE, and
     * it passed while one label — "Setting up payment" — appeared only in the table in that file's
     * header and in no fixture at all (E's finding). A file-text check cannot tell a fixture from a
     * comment, so the real coverage assertion moved to `tests/v3-harness-variants.test.ts`, where the
     * route's exported fixture map is imported and every `pay` is the output of the REAL payControl.
     *
     * What stays here is the property that made the drift possible, closed at the source: the harness
     * may not hand-type a pay control.
     */
    const harness = read('app/_dev/v3-checkout.tsx');
    expect(harness).toContain("import { payControl, type PayControlInput } from '@/src/lib/checkout/payControl';");
    expect(harness).toMatch(/const pay = \(over: Partial<PayControlInput> = \{\}\) => payControl\(\{/);
    // No fixture builds a control by hand — every one of them calls through.
    expect(harness).not.toMatch(/pay: \{\s*label:/);
    expect(harness.match(/pay: pay\(/g)?.length, 'every state resolves its control').toBeGreaterThanOrEqual(11);
    expect(harness).toContain('export const CHECKOUT_STATES');
  });

  it("CV10 (B's review of d374bd3f, resolved with E): ONE carrier for an in-flight status, and it is not dimmed", () => {
    /*
     * The route this took, recorded because the middle step was wrong. B measured that a state whose
     * only words were the pay control's label put the news in a control at 40% opacity. My first fix
     * added those words to the body — which then stated the same status twice at full strength once
     * the second fix stopped dimming a busy control, and E caught that. The resolution is one carrier:
     * the pending label, at full strength, announcing itself.
     */
    expect(src).not.toMatch(/payStatus/);                       // the body row is gone
    expect(src).not.toMatch(/<Spinner label=\{pay\.label\}/);   // and its spinner with it
    const button = code('src/components/ui/Button.tsx');
    expect(button).toContain('disabled && !showPending && styles.disabled,');
    expect(button).toMatch(/accessibilityLiveRegion=\{showPending \? 'polite' : 'none'\}/);
    // The control is still inert while busy, so nothing about interactivity moved.
    expect(button).toContain('const inert = disabled || loading;');
    expect(button).toContain('disabled={inert}');
  });

  it('CV8: the view formats no money, and states no payout STATE or refund figure of its own', () => {
    expect(src).not.toMatch(/formatCents|toFixed|\$\{.*cents/i);
    /*
     * RETARGETED: the confirmation face now carries A's §2f recourse sentence, which names the
     * payout — "a report freezes the seller's payout" — because that is the one true thing to tell a
     * buyer about their money after checkout. What the view still may not do is assert a payout or
     * refund STATE, which only the server's own fields establish.
     */
    expect(src).toContain("a report freezes the seller's payout");
    expect(src).not.toMatch(/payout (has been |was )?(released|reversed|pending|on hold)/i);
    expect(src).not.toMatch(/refunded|refund of|released to/i);
    expect(src).not.toMatch(/automatic/i);
    // And the withdrawn claim is gone: nothing here ties the money to delivery.
    expect(src).not.toMatch(/held until|until it reaches|until your ticket/i);
  });
});
