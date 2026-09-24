/**
 * What the app is allowed to say when it could not reach the eligibility check
 * (owner 2026-09-24: "for transient eligibility-check errors, stop presenting invented account-
 * history claims… preserve current submission behaviour for this presentation fix").
 *
 * `runRiskCheck` fails OPEN on a transient error — a network failure, a timeout, an RPC error — and
 * that is deliberate. But it also set the banner to `medium_risk_warning`, whose copy is "We've
 * noticed some recent issues. Please double-check your listing details." Nobody noticed anything:
 * the request never reached the server, and the server said nothing about this seller. A genuine
 * medium verdict and a failed request rendered identically, and the banner is sticky — it clears
 * only on a later `ok` or a successful publish.
 *
 * The fix is presentation only. Submission still proceeds; the sentence now describes what actually
 * happened.
 */
import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';

const read = (rel: string) => readFileSync(rel, 'utf8')
  .replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

describe('the eligibility check says only what it knows', () => {
  it('EC1: a transient failure no longer claims the account has a history', () => {
    const screen = read('src/screens/CreateListingScreen.tsx');
    const transient = screen.slice(screen.indexOf("case 'transient':"), screen.indexOf("case 'bad_shape':"));
    expect(transient).not.toContain('medium_risk_warning');
    expect(transient).toContain("reason: 'check_unavailable'");
    // Submission behaviour is unchanged: it still fails open.
    expect(transient).toContain('return true');
  });

  it('EC2: the copy describes the failure, and asserts nothing about the seller', () => {
    const copy = read('src/lib/sell/sellState.ts');
    const line = copy.split('\n').find((l) => l.includes('check_unavailable:'));
    expect(line, 'check_unavailable needs copy').toBeTruthy();
    // It must not borrow the vocabulary of a verdict.
    expect(line).not.toMatch(/noticed|recent issues|under review|restrictions|cannot create/i);
    expect(line).toMatch(/could ?n.t|unable/i);
  });

  it('EC3: a failed check reads as neutral, not as a warning', () => {
    const screen = read('src/screens/CreateListingScreen.tsx');
    expect(screen).toMatch(/riskBanner\.reason === 'check_unavailable' && sx\.riskBannerNeutral/);
    expect(screen).toMatch(/riskBannerNeutral:\s+\{ borderColor: p\.border\.control \}/);
  });

  it('EC4: "Contact support" is offered with a way to reach it, and the two blocked reasons stay identical', () => {
    const screen = read('src/screens/CreateListingScreen.tsx');
    // The two less serious gates in the same function already hand over a button; the most serious
    // one told the user to contact support and offered no route at all.
    const block = screen.slice(screen.indexOf("case 'block':"), screen.indexOf("case 'warn':"));
    expect(block).toContain("'/settings/support'");
    expect(block).toMatch(/text: 'Contact support'/);
    // Confirmed with A's reading of the server: `critical_risk` and `listing_blocked` differ in
    // origin and in how they clear, but the USER's action is the same in both — contact support.
    // So they keep one sentence and one treatment; the internal classification is not exposed.
    const copy = read('src/lib/sell/sellState.ts');
    const crit = copy.match(/critical_risk:\s+'([^']+)'/)?.[1];
    const blocked = copy.match(/listing_blocked:\s+'([^']+)'/)?.[1];
    expect(crit).toBe(blocked);
  });

  it('EC5: both risk alerts reach a web user, like every other alert in this screen', () => {
    const screen = read('src/screens/CreateListingScreen.tsx');
    // react-native-web implements Alert.alert as an empty function, so an unguarded alert is
    // silently swallowed; `bad_shape` then refuses to publish with no feedback whatsoever.
    const risk = screen.slice(screen.indexOf('async function runRiskCheck'), screen.indexOf("case 'warn':"));
    const alerts = risk.match(/Alert\.alert\(/g) ?? [];
    const guards = risk.match(/Platform\.OS === 'web'/g) ?? [];
    expect(alerts.length).toBeGreaterThan(0);
    expect(guards.length).toBe(alerts.length);
  });
});

/**
 * B's review at 404bce38 left two actionable defects. Both are fixed below; neither is in build 24,
 * which was authorised at that commit.
 */
describe("B's two remaining findings at 404bce38", () => {
  it('EC6: the blocked BANNER offers the support route too, not only the transient alert', () => {
    const screen = read('src/screens/CreateListingScreen.tsx');
    const banner = screen.slice(screen.indexOf('{riskBanner && riskBanner.reason'), screen.indexOf('Sticky bar'));
    // The alert is dismissible and the banner persists, so a seller who taps "Not now" was left
    // reading "Contact support." on a surface with no way to do it — the very defect the alert fix
    // addressed. The action is identical for both blocked reasons, so it exposes no classification.
    expect(banner).toMatch(/riskBlocked/);
    expect(banner).toMatch(/accessibilityRole="button"/);
    expect(banner).toMatch(/'\/settings\/support'/);
    expect(banner).toMatch(/accessibilityRole="alert"/);   // the container keeps it
    // It appears only for the blocked pair — not on the neutral or warning banners.
    expect(banner).toMatch(/riskBlocked \? \(/);
  });

  it('EC7: a cancelled seller card says "Cancelled" once', () => {
    const card = read('src/components/SellerListingCard.tsx');
    // The Badge carries the word and a11yLabel already includes it via sellerBadgeLabel(badge).
    // The pkg3/pkg8 boards print the word a second time as a bottom line; this ruling wins.
    const slot = card.slice(card.indexOf('<View style={s.bottomLeft}>'), card.indexOf('</View>', card.indexOf('<View style={s.bottomLeft}>')));
    expect(slot).not.toMatch(/>Cancelled</);
    expect(card).toMatch(/<Badge label=\{sellerBadgeLabel\(badge\)\}/);
    // The other branches of the same slot are untouched: each adds something the badge does not say.
    expect(slot).toMatch(/timeLeftLabel/);
    expect(slot).toMatch(/Winner selected/);
    expect(slot).toMatch(/Action needed — send the tickets/);
    // RETARGETED 2026-09-24 (V3 my-listings): the sale date moved from this slot to the board's
    // meta line, through the locale-fixed soldOnLabel — it still renders exactly once.
    expect(slot).not.toMatch(/soldOnLabel|Sold \{new Date/);
    expect(card).toMatch(/badge === 'sold' && listing\.sold_at \? soldOnLabel\(listing\.sold_at\) : bidMeta/);
  });
});
