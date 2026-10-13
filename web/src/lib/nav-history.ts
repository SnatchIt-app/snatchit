/**
 * The pages of this app the current tab has visited, as a stack. Client
 * navigations never change document.referrer, so a back control cannot tell
 * from the referrer alone that history.back() would land on a page of this
 * site (restoring its filters and scroll) rather than leave it.
 *
 * A location equal to the one below the top is a step back (pop); anything
 * else is a new page (push). Module state: lives for the document, resets on
 * a full reload. Pure functions over an explicit stack for the tests.
 */
export function nextStack(stack: readonly string[], url: string): string[] {
  if (stack.length >= 2 && stack[stack.length - 2] === url) return stack.slice(0, -1);
  if (stack[stack.length - 1] === url) return [...stack];
  return [...stack, url];
}

let visited: string[] = [];

export function noteLocation(url: string): void {
  visited = nextStack(visited, url);
}

/** True when an earlier page of this app sits directly behind the current one. */
export function hasInAppHistory(): boolean {
  return visited.length > 1;
}
