/**
 * F-NAV-1 — "Keep editing" must keep Edit listing open, from a swipe back and from the Back button.
 *
 * Device observation (owner, Build 18, DV-S2 step 3): the Discard path passed, but tapping
 * "Keep editing" also landed on My Listings instead of the listing being edited.
 *
 * Cause (source): the unsaved-changes guard subscribed to `beforeRemove` and called
 * `preventDefault()`. On native-stack that only holds navigation STATE. An iOS swipe is carried
 * out by UIKit before JavaScript hears of it: without `preventNativeDismiss` (which native-stack
 * derives only from `usePreventRemove` registrations) the pop completes natively, then
 * `onDismissed` dispatches a pop, the guard refuses it and shows the prompt over My Listings.
 * "Discard" replays the pop and state catches up, so Discard looked right; "Keep editing" does
 * nothing, so the seller stays on My Listings with the edit route still in state but no longer on
 * screen. The Back button (`router.back()`) starts in JavaScript, so the refusal happens before
 * anything moves — that path was expected to hold on Build 18, though no device has exercised it.
 *
 * These tests run the REAL Edit listing screen and the REAL guard hook, with React Navigation's
 * real core and stack router, over a native-stack/iOS model pinned below to the installed library
 * source (tests/helpers/nav-stack-harness.ts). Typed text is read back from the screen's own
 * Event name field after the prompt closes. They do not replace the device row.
 */
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { createStack, findElement, REPO_ROOT, type StackHarness } from './helpers/nav-stack-harness';

const h = vi.hoisted(() => ({
  alerts: [] as { title: string; message?: string; buttons: { text?: string; style?: string; onPress?: () => void }[] }[],
  routerBack: { current: () => {} },
  updates: [] as unknown[],
  user: { id: 'seller-1' },
  listing: {
    id: 'listing-1',
    seller_id: 'seller-1',
    event_name: 'Weekend pool party at the rooftop',
    venue: 'LIV Miami',
    restrictions: null,
    ticket_platform: 'dice',
    bid_count: 0,
    auction_status: 'active',
  },
}));

vi.mock('@react-navigation/native', async () => await import('@react-navigation/core'));
// The migrated screens read the resolved appearance. These suites assert behaviour, not colour, so
// the boundary is mocked to Midnight — whose values ARE the v2 tokens, so nothing they pin moves.
vi.mock('@/src/theme/appearance', async () => {
  const { dark } = await import('@/src/theme/palette');
  return {
    useTheme: () => ({ scheme: 'dark', palette: dark }),
    useAppearancePreference: () => ({ preference: 'system', setPreference: () => {} }),
  };
});
vi.mock('react-native', () => ({
  Alert: {
    alert: (title: string, message?: string, buttons?: { text?: string; style?: string; onPress?: () => void }[]) => {
      h.alerts.push({ title, message, buttons: buttons ?? [] });
    },
  },
  Platform: { OS: 'ios' },
  StyleSheet: { create: <T,>(styles: T) => styles },
  KeyboardAvoidingView: 'KeyboardAvoidingView',
  ScrollView: 'ScrollView',
  Text: 'Text',
  TextInput: 'TextInput',
  View: 'View',
}));
vi.mock('expo-router', () => ({
  router: { back: () => h.routerBack.current() },
  useLocalSearchParams: () => ({ id: 'listing-1' }),
}));
vi.mock('@/src/lib/nav/navInsets', () => ({ useTopInset: () => 0 }));
vi.mock('@/src/hooks/useAuth', () => ({ useAuth: () => ({ user: h.user }) }));
vi.mock('@/src/lib/supabase', () => ({
  supabase: {
    from: () => ({
      select: () => ({ eq: () => ({ single: async () => ({ data: h.listing, error: null }) }) }),
      update: (row: unknown) => {
        h.updates.push(row);
        return { eq: () => ({ eq: async () => ({ error: null }) }) };
      },
    }),
  },
}));
vi.mock('@/src/components/ui', () => ({
  Button: 'Button', Chip: 'Chip', IconButton: 'IconButton', Input: 'Input', Spinner: 'Spinner', StickyBar: 'StickyBar',
}));
vi.mock('@/src/theme/typography', () => ({ textStyle: () => ({}) }));

const MY_LISTINGS = 'my-listings';
const EDIT = 'listing/edit/[id]';
const ORIGINAL = h.listing.event_name;
const TYPED = `${ORIGINAL}abc`;

async function openEditListing(): Promise<StackHarness> {
  const { default: EditListingScreen } = await import('@/app/listing/edit/[id]');
  const stack = await createStack([
    { name: MY_LISTINGS },
    { name: EDIT, params: { id: 'listing-1' }, component: () => EditListingScreen() },
  ]);
  h.routerBack.current = () => stack.containerGoBack();
  for (let i = 0; i < 5; i++) await new Promise((r) => setImmediate(r));   // the listing load resolves
  expect(eventNameValue(stack)).toBe(ORIGINAL);
  return stack;
}

function eventName(stack: StackHarness) {
  const host = stack.host(EDIT);
  return host?.mounted ? findElement(host.output, (el) => el.type === 'Input' && el.props.label === 'Event name') : undefined;
}
function eventNameValue(stack: StackHarness): unknown {
  return eventName(stack)?.props.value;
}
function typeEventName(stack: StackHarness, text: string): void {
  (eventName(stack)!.props.onChangeText as (t: string) => void)(text);
}
function tapBackButton(stack: StackHarness): void {
  const back = findElement(stack.host(EDIT)!.output, (el) => el.type === 'IconButton' && el.props.accessibilityLabel === 'Back');
  (back!.props.onPress as () => void)();
}
/** Let pending promises and microtasks run, so a late reload or reset of the form would show. */
async function settle(): Promise<void> {
  for (let i = 0; i < 5; i++) await new Promise((r) => setImmediate(r));
}
function answerPrompt(label: string): void {
  const prompt = h.alerts.shift();
  expect(prompt?.title).toBe('Discard changes?');
  const button = prompt!.buttons.find((b) => b.text === label);
  expect(button, `prompt button ${label}`).toBeDefined();
  button!.onPress?.();
}

beforeEach(() => {
  h.alerts.length = 0;
  h.updates.length = 0;
});

const PATHS: { path: string; leave: (stack: StackHarness) => void }[] = [
  { path: 'swipe back', leave: (stack) => stack.swipeBack() },
  { path: 'Back button', leave: tapBackButton },
];

for (const { path, leave } of PATHS) {
  describe(`F-NAV-1 · ${path} from Edit listing with unsaved edits`, () => {
    it('opening the prompt does not navigate: Edit listing is still on screen and in navigation state', async () => {
      const stack = await openEditListing();
      typeEventName(stack, TYPED);
      leave(stack);

      expect(h.alerts.map((a) => [a.title, a.message, a.buttons.map((b) => b.text)])).toEqual([
        ['Discard changes?', "Your edits to this listing haven't been saved.", ['Keep editing', 'Discard']],
      ]);
      expect(stack.nativeRoutes()).toEqual([MY_LISTINGS, EDIT]);
      expect(stack.jsRoutes()).toEqual([MY_LISTINGS, EDIT]);
      expect(stack.removedNativelyButKept).toEqual([]);
    });

    it('Keep editing: Edit listing stays open and mounted, and Event name still holds the typed text', async () => {
      const stack = await openEditListing();
      const host = stack.host(EDIT);
      typeEventName(stack, TYPED);
      leave(stack);
      answerPrompt('Keep editing');
      await settle();

      expect(stack.nativeRoutes()).toEqual([MY_LISTINGS, EDIT]);
      expect(stack.jsRoutes()).toEqual([MY_LISTINGS, EDIT]);
      expect(stack.host(EDIT)).toBe(host);
      expect(host?.mounted).toBe(true);
      expect(eventNameValue(stack)).toBe(TYPED);
      expect(h.updates).toEqual([]);
      expect(h.alerts).toEqual([]);
    });

    it('Keep editing, then leaving again asks again', async () => {
      const stack = await openEditListing();
      typeEventName(stack, TYPED);
      leave(stack);
      answerPrompt('Keep editing');
      await settle();
      leave(stack);

      expect(h.alerts.map((a) => a.title)).toEqual(['Discard changes?']);
      expect(stack.nativeRoutes()).toEqual([MY_LISTINGS, EDIT]);
      expect(eventNameValue(stack)).toBe(TYPED);
    });

    it('Discard: back on My Listings without saving, after a single prompt', async () => {
      const stack = await openEditListing();
      const host = stack.host(EDIT);
      typeEventName(stack, TYPED);
      leave(stack);
      answerPrompt('Discard');

      expect(stack.nativeRoutes()).toEqual([MY_LISTINGS]);
      expect(stack.jsRoutes()).toEqual([MY_LISTINGS]);
      expect(host?.mounted).toBe(false);
      expect(h.updates).toEqual([]);
      expect(h.alerts).toEqual([]);
    });

    it('no unsaved edits: leaves at once, without a prompt', async () => {
      const stack = await openEditListing();
      leave(stack);

      expect(h.alerts).toEqual([]);
      expect(stack.nativeRoutes()).toEqual([MY_LISTINGS]);
      expect(stack.jsRoutes()).toEqual([MY_LISTINGS]);
      expect(stack.removedNativelyButKept).toEqual([]);
    });

    it('edits typed and then undone: leaves at once, without a prompt', async () => {
      const stack = await openEditListing();
      typeEventName(stack, TYPED);
      typeEventName(stack, ORIGINAL);
      leave(stack);

      expect(h.alerts).toEqual([]);
      expect(stack.nativeRoutes()).toEqual([MY_LISTINGS]);
      expect(stack.jsRoutes()).toEqual([MY_LISTINGS]);
    });
  });
}

// Repeated attempts, in every order of the two ways out (D review of 2ba9e3a).
const ORDERS: [string, (stack: StackHarness) => void, string, (stack: StackHarness) => void][] = [
  ['swipe back', (stack) => stack.swipeBack(), 'swipe back', (stack) => stack.swipeBack()],
  ['Back button', tapBackButton, 'Back button', tapBackButton],
  ['swipe back', (stack) => stack.swipeBack(), 'Back button', tapBackButton],
  ['Back button', tapBackButton, 'swipe back', (stack) => stack.swipeBack()],
];

for (const [first, leaveFirst, second, leaveSecond] of ORDERS) {
  describe(`F-NAV-1 · repeat · ${first} then ${second}`, () => {
    it('Keep editing twice keeps the screen and the typed text each time', async () => {
      const stack = await openEditListing();
      const host = stack.host(EDIT);
      typeEventName(stack, TYPED);
      leaveFirst(stack);
      answerPrompt('Keep editing');
      await settle();
      leaveSecond(stack);
      answerPrompt('Keep editing');
      await settle();

      expect(stack.nativeRoutes()).toEqual([MY_LISTINGS, EDIT]);
      expect(stack.jsRoutes()).toEqual([MY_LISTINGS, EDIT]);
      expect(stack.host(EDIT)).toBe(host);
      expect(eventNameValue(stack)).toBe(TYPED);
      expect(stack.removedNativelyButKept).toEqual([]);
      expect(h.alerts).toEqual([]);
    });

    it('Keep editing, then Discard leaves without saving after exactly one more prompt', async () => {
      const stack = await openEditListing();
      typeEventName(stack, TYPED);
      leaveFirst(stack);
      answerPrompt('Keep editing');
      await settle();
      leaveSecond(stack);
      answerPrompt('Discard');
      await settle();

      expect(stack.nativeRoutes()).toEqual([MY_LISTINGS]);
      expect(stack.jsRoutes()).toEqual([MY_LISTINGS]);
      expect(h.updates).toEqual([]);
      expect(h.alerts).toEqual([]);
    });
  });
}

// ── The model above is only as good as its match with the installed libraries ──

const lib = (p: string) => readFileSync(join(REPO_ROOT, 'node_modules', p), 'utf8');
const version = (pkg: string) => (JSON.parse(lib(`${pkg}/package.json`)) as { version: string }).version;

describe('the modelled native layer still matches the installed library source', () => {
  it('was checked against these versions (an upgrade must re-check the model)', () => {
    expect({
      core: version('@react-navigation/core'),
      routers: version('@react-navigation/routers'),
      nativeStack: version('@react-navigation/native-stack'),
      screens: version('react-native-screens'),
      expoRouter: version('expo-router'),
    }).toEqual({ core: '7.16.1', routers: '7.5.3', nativeStack: '7.14.4', screens: '4.16.0', expoRouter: '6.0.24' });
  });

  it('native-stack: iOS preventNativeDismiss comes only from usePreventRemove registrations; both native outcomes dispatch pop', () => {
    const view = lib('@react-navigation/native-stack/src/views/NativeStackView.native.tsx');
    expect(view).toContain('const { preventedRoutes } = usePreventRemoveContext();');
    expect(view).toContain('const isRemovePrevented = preventedRoutes[route.key]?.preventRemove;');
    expect(view).toContain('preventNativeDismiss={isRemovePrevented} // on iOS');
    expect(view).toMatch(/onDismissed=\{\(event\) => \{\s*navigation\.dispatch\(\{\s*\.\.\.StackActions\.pop\(event\.nativeEvent\.dismissCount\),\s*source: route\.key,/);
    expect(view).toMatch(/onNativeDismissCancelled=\{\(event\) => \{\s*navigation\.dispatch\(\{\s*\.\.\.StackActions\.pop\(event\.nativeEvent\.dismissCount\),\s*source: route\.key,/);
    expect(lib('@react-navigation/native-stack/src/utils/useDismissedRouteError.tsx'))
      .toContain("was removed natively but didn't get removed from JS state");
  });

  it('react-native-screens iOS: a prevented swipe is cancelled natively; otherwise the pop completes before JS is told', () => {
    const screen = lib('react-native-screens/ios/RNSScreen.mm');
    expect(screen).toMatch(/if \(self\.screenView\.preventNativeDismiss\) \{[\s\S]{0,300}\[self\.screenView\.reactSuperview updateContainer\];\s*\[self\.screenView notifyDismissCancelledWithDismissCount:_dismissCount\];\s*\} else \{[\s\S]{0,60}\[self\.screenView notifyDismissedWithCount:_dismissCount\];/);
    const stack = lib('react-native-screens/ios/RNSScreenStack.mm');
    expect(stack).toMatch(/shouldCancelDismissFromView[\s\S]{0,300}if \(_reactSubviews\[i\]\.preventNativeDismiss\) \{\s*return YES;/);
    expect(stack).toContain('we check reactSuperview since this method also fires when');
    expect(stack).toContain('if (_interactionController == nil && fromView.reactSuperview) {');
  });

  it('core: usePreventRemove registers the route and holds beforeRemove; PreventRemoveProvider keys registrations by id', () => {
    const hook = lib('@react-navigation/core/lib/module/usePreventRemove.js');
    expect(hook).toContain('setPreventRemove(id, routeKey, preventRemove);');
    expect(hook).toMatch(/if \(!preventRemove\) \{\s*return;\s*\}\s*e\.preventDefault\(\);\s*callback\(\{\s*data: e\.data\s*\}\);/);
    const provider = lib('@react-navigation/core/lib/module/PreventRemoveProvider.js');
    expect(provider).toMatch(/if \(preventRemove\) \{\s*nextPrevented\.set\(id, \{\s*routeKey,\s*preventRemove\s*\}\);\s*\} else \{\s*nextPrevented\.delete\(id\);/);
    expect(provider).toContain('preventRemove: acc[routeKey]?.preventRemove || preventRemove');
    const cache = lib('@react-navigation/core/lib/module/useNavigationCache.js');
    expect(cache).toMatch(/navigation\.dispatch\(\{\s*source: route\.key,\s*\.\.\.action\s*\}\);/);
  });

  it("expo-router: router.back() queues GO_BACK for the container; Edit listing's Back button calls it; every route is a card push", () => {
    const routing = lib('expo-router/build/global-state/routing.js');
    expect(routing).toMatch(/function goBack\(\) \{[\s\S]{0,160}exports\.routingQueue\.add\(\{ type: 'GO_BACK' \}\);/);
    expect(routing).toMatch(/while \(\(action = events\.shift\(\)\)\) \{\s*if \(ref\.current\) \{\s*ref\.current\.dispatch\(action\);/);
    const edit = readFileSync(join(REPO_ROOT, 'app/listing/edit/[id].tsx'), 'utf8');
    expect(edit).toContain('<IconButton glyph="back" onPress={() => router.back()} accessibilityLabel="Back" />');
    // expo-router's Stack is its own fork of the navigator, but it renders upstream native-stack's view,
    // so the NativeStackView pins above describe the running code (D review of 2ba9e3a).
    expect(lib('expo-router/build/layouts/StackClient.js')).toContain('require("../fork/native-stack/createNativeStackNavigator")');
    const fork = lib('expo-router/build/fork/native-stack/createNativeStackNavigator.js');
    expect(fork).toContain('const native_stack_1 = require("@react-navigation/native-stack");');
    expect(fork).toContain('(0, native_1.useNavigationBuilder)(native_1.StackRouter, {');
    expect(fork).toMatch(/<NavigationContent>\s*<native_stack_1\.NativeStackView \{\.\.\.rest\}/);
    const layout = readFileSync(join(REPO_ROOT, 'app/_layout.tsx'), 'utf8');
    expect(layout).toContain("import { router, Stack } from 'expo-router';");
    expect(layout).not.toMatch(/presentation:\s*'(modal|formSheet|transparentModal|fullScreenModal)'/);
  });
});
