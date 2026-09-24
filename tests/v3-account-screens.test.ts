/**
 * V3 account surfaces — Profile, Settings hub, Appearance, and the auth screens'
 * presentation — pinned to the approved pkg8 boards AND to the functional freeze the
 * batch promised: zero drift in the auth calls, the avatar publication chain, and the
 * appearance-preference machinery. Source contracts: comments stripped, then exact
 * strings, so a "restyle" that rewired a call fails here before it reaches review.
 *
 * Boards: pkg8-account-tickets-{dark,light} (Profile), pkg8-account-settings-{dark,light}
 * (Settings hub + banners), pkg8-appearance-{dark,light} (Appearance), pkg8-account-auth-
 * {dark,light} (auth presentation). Harness: app/_dev/v3-account.tsx.
 */
import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';

const read = (rel: string) => readFileSync(rel, 'utf8')
  .replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

// ─── Profile (pkg8-account-tickets · PROFILE · own) ─────────────────────────────

describe('Profile — the board, over an untouched data layer', () => {
  const src = read('app/(tabs)/profile.tsx');

  it('P1: tab-root header — sentence-case title, quiet trailing Settings action', () => {
    expect(src).toMatch(/textStyle\('screenTitle'\), s\.headerTitle\]\} accessibilityRole="header">Profile</);
    expect(src).toMatch(/textStyle\('action'\), s\.headerAction\]\}>Settings</);
    expect(src).not.toMatch(/textStyle\('label'\)/); // no V2 uppercase-tracked action label survives
  });

  it('P2: identity is avatar-left with the display name in the display face', () => {
    expect(src).toMatch(/textStyle\('nameState'\), s\.name\]/);
    expect(src).toMatch(/identity: \{\s*flexDirection: 'row'/);
  });

  it('P3: the red avatar ring is gone — red is never passive decoration (A-1)', () => {
    expect(src).not.toMatch(/avatarRing/);
    expect(src).not.toMatch(/borderColor: p\.brand\.red/);
  });

  it('P4: SELLER renders the board\'s stacked label/value rows, and unknown proceeds stay "—"', () => {
    expect(src).toMatch(/<StatRow s=\{s\} label="Active"/);
    expect(src).toMatch(/<StatRow s=\{s\} label="Sold"/);
    expect(src).toMatch(/<StatRow s=\{s\} label="Proceeds" value=\{stats\.revenue > 0 \? formatDollars\(stats\.revenue\) : '—'\}/);
    // The V2 three-up stat strip is gone.
    expect(src).not.toMatch(/statDivider/);
    expect(src).not.toMatch(/textStyle\('price'\), s\.statValue/);
  });

  it('P5: the avatar publication chain is byte-identical (freshly fixed, A-adjacent)', () => {
    expect(src).toContain('setAvatarUrl(getAvatarUrl(p.avatar_path ?? p.avatar_url));');
    expect(src).toContain('setDockAvatar(user.id, p.avatar_path ?? p.avatar_url);');
    expect(src).toContain('setDockAvatar(user.id, result.storagePath);');
    expect(src).toContain('const result = await pickAndUploadAvatar(user.id);');
  });

  it('P6: the harness fixture replaces the reads and only the reads — no fabricated session', () => {
    // Fixture mode returns before loadData ever runs; the fixture type carries display literals only.
    expect(src).toMatch(/if \(fixture\) \{\s*setProfile\(fixture\.profile\);/);
    expect(src).toMatch(/export type ProfileFixture/);
    expect(src).not.toMatch(/fixture[^\n]*session/i);
    // The live sign-out path is untouched.
    expect(src).toContain('const r = await signOutThisDevice();');
  });
});

// ─── Settings hub (pkg8-account-settings) ───────────────────────────────────────

describe('Settings hub — board banners over the untouched OR-17 machine', () => {
  const src = read('app/settings/index.tsx');

  it('S1: pushed-screen header — circular back chip, sentence-case title, no V2 display token', () => {
    expect(src).toMatch(/IconButton glyph="back" chip/);
    expect(src).toMatch(/textStyle\('screenTitle'\), s\.headerTitle\]\} accessibilityRole="header">Settings</);
    expect(src).not.toMatch(/textStyle\('displaySm'\)/);
  });

  it('S2: the deletion-pending banner is the board\'s warning accent panel with an OUTLINED withdraw', () => {
    expect(src).toMatch(/pendingBanner: \{[^}]*borderLeftColor: p\.status\.warning/s);
    expect(src).toMatch(/label="Withdraw deletion request"\s*variant="secondary"/);
  });

  it('S3: the failed-probe banner keeps the tri-state honest — error accent, Retry, never "not pending"', () => {
    expect(src).toMatch(/probeBanner: \{[^}]*borderLeftColor: p\.status\.error/s);
    expect(src).toMatch(/textStyle\('action'\), s\.retry\]\}>Retry</);
    // The tri-state machine and its ambiguity guard are byte-identical.
    expect(src).toContain("if (!ext && deletionView === 'pending') { setDeletionProbeFailed(true); return; }");
    expect(src).toContain("if (ext?.deletion_state === 'DELETION_PENDING') { setDeletionView('pending'); return; }");
  });

  it('S4: the harness fixture seeds the tri-state as a literal and skips the probe entirely', () => {
    expect(src).toMatch(/if \(deletionFixture\) \{\s*setDeletionView\(deletionFixture === 'probe_failed' \? 'unknown' : deletionFixture\);/);
    expect(src).toMatch(/export type SettingsDeletionFixture = 'active' \| 'pending' \| 'probe_failed'/);
  });

  it('S5: every account action keeps its guard — confirms and calls unchanged', () => {
    expect(src).toContain("Alert.alert('Sign out', 'Are you sure you want to sign out?'");
    expect(src).toContain("'Sign out of all devices',");
    expect(src).toContain("supabase.functions.invoke('delete-account', { body: { action: 'withdraw' } })");
    expect(src).toContain("supabase.functions.invoke('delete-account', { body: {} })");
    expect(src).toContain("'Are you absolutely sure?',");
  });
});

// ─── Appearance (pkg8-appearance) ───────────────────────────────────────────────

describe('Appearance — board radios over untouched preference machinery', () => {
  const src = read('app/settings/appearance.tsx');

  it('A1: the three stored values and the setPreference wiring are untouched', () => {
    expect(src).toMatch(/\{ key: 'system', label: 'System', description: 'Follows your phone' \}/);
    expect(src).toMatch(/\{ key: 'light', label: 'Light' \}/);
    expect(src).toMatch(/\{ key: 'dark', label: 'Dark' \}/);
    expect(src).toContain('onPress={() => setPreference(o.key)}');
    expect(src).toContain('const { preference, setPreference } = useAppearancePreference();');
  });

  it('A2: rounded filled rows; selection is the radio alone — no tinted or re-bordered row', () => {
    expect(src).toMatch(/row: \{[^}]*borderRadius: v2\.radius\.md/s);
    expect(src).toMatch(/backgroundColor: p\.surface\.surface/);
    expect(src).not.toMatch(/rowChecked/);
    expect(src).not.toMatch(/redSoft/);
  });

  it('A3: the radio — graded ring at rest, brand-red ring and dot when chosen', () => {
    expect(src).toMatch(/radio: \{[^}]*borderColor: p\.border\.control/s);
    expect(src).toMatch(/radioChecked: \{ borderWidth: 2, borderColor: p\.brand\.red \}/);
    expect(src).toMatch(/radioDot: \{[^}]*backgroundColor: p\.brand\.red/s);
    expect(src).toMatch(/accessibilityState=\{\{ checked: checked \}\}/);
  });

  it('A4: pushed-screen header, and the old check-mark treatment is gone', () => {
    expect(src).toMatch(/IconButton glyph="back" chip/);
    expect(src).toMatch(/textStyle\('screenTitle'\), s\.headerTitle\]\} accessibilityRole="header">Appearance</);
    expect(src).not.toMatch(/'✓'/);
  });
});

// ─── Auth presentation (pkg8-account-auth) ──────────────────────────────────────

describe('Auth screens — board presentation, frozen flows', () => {
  const login = read('app/(auth)/login.tsx');
  const signup = read('app/(auth)/signup.tsx');
  const reset = read('app/(auth)/reset-password.tsx');

  it('L1: every supabase.auth call on Sign in keeps its exact shape', () => {
    expect(login).toContain('const { error: otpErr } = await supabase.auth.signInWithOtp({');
    expect(login).toContain('options: { shouldCreateUser: false },');
    expect(login).toContain('const { error: verifyErr } = await supabase.auth.verifyOtp({');
    expect(login).toContain("type: 'sms',");
    expect(login).toContain('const { error: authErr } = await supabase.auth.signInWithPassword({ email: email.trim(), password });');
    expect(login).toContain("const { error: resetErr } = await supabase.auth.resetPasswordForEmail(email.trim(), { redirectTo: 'snatchit://' });");
  });

  it('L2: the marked sign-out notice is the warning accent banner, ABOVE the title', () => {
    expect(login).toMatch(/noticeBanner: \{[^}]*borderLeftColor: p\.status\.warning/s);
    const phoneBranch = login.indexOf("step === 'enter_phone'");
    const noticeAt = login.indexOf('{noticeRow}', phoneBranch);
    const titleAt = login.indexOf('>Sign in</', phoneBranch);
    expect(noticeAt).toBeGreaterThan(-1);
    expect(noticeAt).toBeLessThan(titleAt);
  });

  it('L3: the method switches are the board\'s outlined pills; titles are sentence-case', () => {
    expect(login).toMatch(/label="Use email instead" variant="secondary"/);
    expect(login).toMatch(/label="Use mobile number instead" variant="secondary"/);
    expect(login).toMatch(/textStyle\('screenTitle'\), s\.title\]\} accessibilityRole="header">Verify number</);
    expect(login).not.toMatch(/textStyle\('displayLg'\)/);
  });

  it('G1: signup keeps every provider call — account, phone change, verify, demographics', () => {
    expect(signup).toContain('const { data, error } = await supabase.auth.signUp({');
    expect(signup).toContain('const { error } = await supabase.auth.updateUser({ phone: e164 });');
    expect(signup).toContain("const { error } = await supabase.auth.verifyOtp({ phone: e164, token: code.trim(), type: 'phone_change' });");
    expect(signup).toContain('setOnboarding(true);');
    expect(signup).toContain(".rpc('set_my_demographics', {");
  });

  it('G2: the step eyebrow is the boards\' warning-ink sentence-case eyebrow', () => {
    expect(signup).toMatch(/textStyle\('sectionLabel'\), s\.progress\]\}>Step \{stepIndex\(step\) \+ 1\} of \{SIGNUP_STEP_COUNT\}</);
    expect(signup).toMatch(/progress: \{ color: p\.status\.warning/);
  });

  it('G3: the legal disclosure sits BELOW the step-1 CTA, as the board orders it', () => {
    const ctaAt = signup.indexOf('label="Continue"\n            onPress={submitAccount}');
    const legalAt = signup.indexOf('By creating an account you agree to our');
    expect(ctaAt).toBeGreaterThan(-1);
    expect(legalAt).toBeGreaterThan(ctaAt);
  });

  it('G4: the 18+ checkbox is rounded with a primary-ink fill — red stays actions', () => {
    expect(signup).toMatch(/checkbox: \{\s*width: 24, height: 24, borderRadius: v2\.radius\.sm/);
    expect(signup).toMatch(/checkboxOn: \{ backgroundColor: p\.text\.primary, borderColor: p\.text\.primary \}/);
    expect(signup).not.toMatch(/checkboxOn: \{ backgroundColor: p\.brand\.red/);
  });

  it('G5: the password rule stays a persistent helper (owner 2026-09-24, FP2) — the board yields', () => {
    expect(signup).toMatch(/helper="At least 6 characters"/);
    expect(signup).not.toMatch(/placeholder="At least 6 characters"/);
  });

  it('R1: reset keeps its exact path — updateUser, then a marked all-device sign-out', () => {
    expect(reset).toContain('const { error } = await supabase.auth.updateUser({ password });');
    expect(reset).toContain("const r = await signOutAllDevices({ reason: 'password_changed' });");
  });
});

// ─── Harness (app/_dev/v3-account.tsx) ─────────────────────────────────────────

describe('v3-account harness — literals only, gated, no session, no server', () => {
  const src = read('app/_dev/v3-account.tsx');

  it('H1: gated exactly like v3-screens, and it mounts the real screens', () => {
    expect(src).toContain('if (!IS_SANDBOX_BUILD && !__DEV__) return <Redirect href="/" />;');
    expect(src).toContain("import ProfileScreen, { type ProfileFixture } from '@/app/(tabs)/profile';");
    expect(src).toContain("import SettingsScreen, { type SettingsDeletionFixture } from '@/app/settings/index';");
    expect(src).toContain("import AppearanceScreen from '@/app/settings/appearance';");
  });

  it('H2: the required cases exist — profile with and without avatar, settings tri-state, appearance', () => {
    expect(src).toMatch(/case 'noavatar':/);
    expect(src).toContain('avatarUri: AVATAR_DATA_URI');
    expect(src).toMatch(/case 'pending': return 'pending';/);
    expect(src).toMatch(/case 'probe-failed': return 'probe_failed';/);
    expect(src).toMatch(/case 'appearance':/);
    // Appearance selection rides the same store the harness param sets.
    expect(src).toContain('setPreference(appearance);');
  });

  it('H3: the board\'s unknown-proceeds rule survives into the fixture — revenue 0 renders "—"', () => {
    expect(src).toMatch(/stats: \{ active: 2, sold: 7, revenue: 0 \}/);
  });

  it('H4: no supabase import, no fabricated session, avatar is a bundled data uri', () => {
    expect(src).not.toMatch(/supabase/);
    expect(src).not.toMatch(/session/i);
    expect(src).toMatch(/const AVATAR_DATA_URI =\s*'data:image\/png;base64,/);
  });
});
