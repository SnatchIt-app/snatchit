/** The persisted native intent fences later opposite allocations in the DB.
 * Recheck immediately before each new provider POST, including after a search.
 * Provider GET/adoption/state-sync paths do not call this gate.
 */
export async function postFreshRefund<T>(
  authorize: () => PromiseLike<{ data: unknown; error: { message: string } | null }>,
  post: () => Promise<T>,
): Promise<{ kind: 'posted'; response: T } | { kind: 'refused'; reason: string }> {
  let checked: Awaited<ReturnType<typeof authorize>>;
  try {
    checked = await authorize();
  } catch {
    return { kind: 'refused', reason: 'fresh_money_gate_unavailable' };
  }
  if (checked.error) return { kind: 'refused', reason: 'fresh_money_gate_unavailable' };
  const verdict = checked.data as { allowed?: unknown; reason?: unknown } | null;
  if (verdict?.allowed !== true) {
    return { kind: 'refused', reason: typeof verdict?.reason === 'string' ? verdict.reason : 'fresh_money_gate_invalid' };
  }
  return { kind: 'posted', response: await post() };
}
