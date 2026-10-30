/**
 * tests/helpers/screen-view.ts — reading a rendered screen without flattering it.
 *
 * Every screen test in this suite answers one question: what would the user see? The hand-rolled helpers that
 * answered it kept making the same mistake, four times, in four files — they ended with a fallback that named
 * a state instead of admitting the tree was empty:
 *
 *   - Home's `view()` returned 'loading' when nothing rendered, so a mutant that deleted the loading flag
 *     survived (found by the mutant run, HM1).
 *   - Place bid's `view()` returned `{ form: true }` when nothing rendered — a blank screen reported as
 *     "the bid form is up", which is the exact outcome that fix exists to prevent (found by D's review).
 *   - Profile's `busy()` returned `false` for "the control is not on screen" and for "on screen, not busy"
 *     alike, because `findElement` yields undefined rather than throwing (found by D's review).
 *
 * The general fix, rather than a fourth specific one: a verdict is only ever reported when something
 * POSITIVELY identifies it, and "nothing matched" is its own answer — `'blank'` — which no assertion in this
 * suite expects. A helper that cannot say "blank" cannot fail in the safe direction.
 */

import { findElement, type Element } from './nav-stack-harness';

/** Nothing on screen matched any known state. Never an expected verdict — always a failure worth seeing. */
export const BLANK = 'blank' as const;
export type Blank = typeof BLANK;

/** Every string rendered anywhere under `node`, in tree order. */
export function textsOf(node: unknown): string[] {
  const out: string[] = [];
  const walk = (n: unknown): void => {
    if (Array.isArray(n)) { n.forEach(walk); return; }
    const el = n as Element | null;
    if (!el || typeof el !== 'object' || !('props' in el)) return;
    const kids = el.props.children;
    if (typeof kids === 'string') out.push(kids);
    else if (typeof kids === 'number') out.push(String(kids));
    walk(kids);
  };
  walk(node);
  return out;
}

/** Everything the user could read on this screen, as one string — for `toContain` on copy. */
export function screenText(node: unknown): string {
  return textsOf(node).join(' | ');
}

/** Is an element of this type anywhere under `node`? */
export function hasType(node: unknown, type: string): boolean {
  return findElement(node, (el) => el.type === type) !== undefined;
}

/** The element carrying this accessibility label, or undefined. */
export function byLabel(node: unknown, label: string): Element | undefined {
  return findElement(node, (el) => el.props.accessibilityLabel === label);
}

/** The Button (stubbed as a string element) carrying this label, or undefined. */
export function buttonByLabel(node: unknown, ...labels: string[]): Element | undefined {
  return findElement(
    node,
    (el) => el.type === 'Button' && typeof el.props.label === 'string' && labels.includes(el.props.label as string),
  );
}

/**
 * A tri-state read of a control's busy look. `'absent'` is distinct from `false` on purpose: a control that
 * is not on screen is not a control that is idle, and four assertions in the avatar suite used to accept one
 * for the other.
 */
export function busyState(control: Element | undefined, spinnerType = 'Spinner'): 'absent' | boolean {
  if (!control) return 'absent';
  return hasType(control, spinnerType) && control.props.disabled === true;
}
