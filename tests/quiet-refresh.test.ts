/**
 * tests/quiet-refresh.test.ts — content survives a reload (CFT-103).
 *
 * Two live defects: Tickets entered its loading phase on every focus, which
 * unmounted the list and put a spinner over rows already on screen, and Search
 * cleared its results the moment a query failed. The policy behind both screens
 * is the pure module src/lib/screens/refreshPolicy.ts, driven here directly;
 * source guards then pin that the screens actually consult it.
 */

import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import {
  failureSurface,
  phaseAfterError,
  shouldShowLoading,
} from '../src/lib/screens/refreshPolicy';

const root = resolve(__dirname, '..');
/** Comments describe the old behaviour by name; the guards read the code. */
const code = (rel: string) =>
  readFileSync(resolve(root, rel), 'utf8')
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/(^|[^:])\/\/.*$/gm, '$1');
const read = (rel: string) => readFileSync(resolve(root, rel), 'utf8');

describe('refresh policy — the loading state is for a first load only', () => {
  it('shows loading when nothing has been shown yet', () => {
    expect(shouldShowLoading(0, 'loading')).toBe(true);
    expect(shouldShowLoading(0, 'error')).toBe(true);
  });

  it('refreshes quietly over rows', () => {
    expect(shouldShowLoading(3, 'ready')).toBe(false);
    expect(shouldShowLoading(3, 'loading')).toBe(false);
    expect(shouldShowLoading(1, 'error')).toBe(false);
  });

  it('treats a settled empty result as content, not as nothing', () => {
    // "No tickets yet" is a success state; a focus reload must not spin over it.
    expect(shouldShowLoading(0, 'ready')).toBe(false);
  });
});

describe('refresh policy — a failed quiet refresh keeps the screen', () => {
  it('leaves populated content alone', () => {
    expect(phaseAfterError(3, 'ready')).toBe('ready');
    expect(phaseAfterError(1, 'loading')).toBe('loading');
  });

  it('leaves a settled empty state alone', () => {
    expect(phaseAfterError(0, 'ready')).toBe('ready');
  });

  it('shows the error only where the loading state would have been', () => {
    expect(phaseAfterError(0, 'loading')).toBe('error');
    expect(phaseAfterError(0, 'error')).toBe('error');
  });
});

describe('refresh policy — where a search failure is surfaced', () => {
  it('is nowhere when nothing failed', () => {
    expect(failureSurface(0, false)).toBe('none');
    expect(failureSurface(5, false)).toBe('none');
  });

  it('takes the screen only when there are no results to keep', () => {
    expect(failureSurface(0, true)).toBe('screen');
  });

  it('goes inline over results that are still valid', () => {
    expect(failureSurface(1, true)).toBe('inline');
    expect(failureSurface(40, true)).toBe('inline');
  });
});

describe('tickets — shipped-source guards', () => {
  const screen = read('app/(tabs)/tickets.tsx');
  const screenCode = code('app/(tabs)/tickets.tsx');

  it('consults the policy instead of entering the loading phase on every reload', () => {
    expect(screen).toContain("from '@/src/lib/screens/refreshPolicy'");
    // The one place the loading phase is set is behind the policy. The previous
    // shape was `if (!isRefresh) setPhase('loading')`, which fired on every focus.
    const sets = screenCode.match(/setPhase\('loading'\)/g) ?? [];
    expect(sets).toHaveLength(1);
    expect(screenCode).toMatch(/if \(shouldShowLoading\([^)]*\)\) setPhase\('loading'\)/);
    expect(screenCode).not.toMatch(/if \(!isRefresh\) setPhase\('loading'\)/);
  });

  it('keeps rows on a failed refresh and never shows the raw message', () => {
    expect(screenCode).toMatch(/phaseAfterError\(/);
    expect(screenCode).not.toMatch(/setPhase\('error'\)/);
    // The failure goes to the log; the UI keeps whatever it already showed.
    expect(screenCode).toMatch(/console\.warn\('\[tickets\] refresh failed/);
  });

  it('reads what is on screen through a ref, so the focus effect does not refetch on every state change', () => {
    expect(screenCode).toMatch(/const shown = useRef</);
    expect(screenCode).toMatch(/useFocusEffect\(useCallback\(\(\) => \{ load\(\); \}, \[load\]\)\)/);
    expect(screenCode).toMatch(/\}, \[devFixtures\]\);/);
  });

  it('keeps the copy, the header and the dev toggle exactly', () => {
    expect(screen).toContain('title="No tickets yet"');
    expect(screen).toContain('body="Tickets you own will show up here."');
    expect(screen).toContain('>Your tickets</Text>');
    expect(screen).toContain("{devFixtures ? 'DEV FIXTURES ON' : 'DEV'}");
    expect(screen).toContain('<RefreshControl refreshing={refreshing} onRefresh={onRefresh}');
  });
});

describe('search — shipped-source guards', () => {
  const screen = read('app/(tabs)/explore.tsx');
  const screenCode = code('app/(tabs)/explore.tsx');

  it('no longer clears results when a query fails', () => {
    const errorBranch = /if \(error\) \{([\s\S]*?)\n\s*\}/.exec(screenCode)?.[1] ?? '';
    expect(errorBranch, 'runSearch keeps its error branch').not.toBe('');
    expect(errorBranch).not.toMatch(/setResults\(/);
    expect(errorBranch).toMatch(/setLoadError\(/);
    // The short-query reset is the only remaining clear, as before.
    expect(screenCode.match(/setResults\(\[\]\)/g) ?? []).toHaveLength(1);
  });

  it('surfaces the failure inline over kept results, and never with server text', () => {
    expect(screen).toContain("from '@/src/lib/screens/refreshPolicy'");
    expect(screenCode).toMatch(/failureSurface\(results\.length, loadError != null\)/);
    expect(screenCode).toMatch(/failure === 'screen' && loadError \? \(\s*<ScreenState/);
    expect(screenCode).toMatch(/failure === 'inline' && loadError \? \(\s*<SearchFailureNotice/);
    const notice = screenCode.slice(
      screenCode.indexOf('function SearchFailureNotice'),
      screenCode.indexOf('export default function SearchScreen'),
    );
    expect(notice).not.toMatch(/message|error\./);
    expect(notice).toContain('accessibilityLabel="Retry search"');
  });

  it('keeps the query it already had', () => {
    expect(screenCode).toContain(".or(`event_name.ilike.%${clean}%,venue.ilike.%${clean}%`)");
    expect(screenCode).toContain("applyBlockedSellerFilter(base, blockedIds)");
  });
});
