/**
 * src/lib/security/notices.ts — the account-security notices a signed-in user
 * must see (notification batch 1, item 2; owner ruling 2026-09-17; A's 136
 * contract, D-verified copy on the SERVER).
 *
 * `public.get_my_security_notices()` returns the caller's security notices,
 * newest first, ALREADY RENDERED: {id, type_key, title, body, created_at,
 * read_at}. The client shows title and body exactly as returned — it owns no
 * sentence about the event; the only client copy is the two action labels.
 * `public.mark_security_notices_read(p_ids uuid[])` returns the number of the
 * caller's own notices newly marked (0 for foreign ids, already read, null).
 * PGRST202 (migration absent) means "no notices", never an error.
 *
 * `security_device_rebound` means: a device that was receiving THIS account's
 * notifications is now registered to ANOTHER account. It does not mean another
 * device was linked to this account. "Sign out of all devices" (K-2) is safe to
 * offer — revoke_all_push_bindings is auth.uid()-scoped, so it cannot disturb
 * the rebound token or its new owner — and it does NOT undo the rebind, so
 * nothing here implies the device comes back.
 */

export const SECURITY_NOTICES_RPC = 'get_my_security_notices';
export const MARK_NOTICES_READ_RPC = 'mark_security_notices_read';
export const REBOUND_TYPE_KEY = 'security_device_rebound';

export interface SecurityNotice {
  id: string;
  type_key: string;
  title: string;
  body: string;
  created_at: string;
  read_at: string | null;
}

export type NoticeAction = 'sign_out_all' | 'dismiss';

/** The only client copy on this surface. */
export const NOTICE_ACTION_LABEL: Record<NoticeAction, string> = {
  sign_out_all: 'Sign out of all devices',
  dismiss: 'Dismiss',
};

function isNotice(v: unknown): v is SecurityNotice {
  if (!v || typeof v !== 'object') return false;
  const o = v as Record<string, unknown>;
  return typeof o.id === 'string' && typeof o.type_key === 'string' && typeof o.title === 'string' && typeof o.body === 'string'
    && typeof o.created_at === 'string' && (o.read_at === null || typeof o.read_at === 'string');
}

/** Defensive parse of the RPC reply: anything that is not a well-formed row is dropped. */
export function parseSecurityNotices(data: unknown): SecurityNotice[] {
  if (!Array.isArray(data)) return [];
  return data.filter(isNotice);
}

/** The newest unread device-rebound notice, or null. Read notices and other types are not shown here. */
export function selectActionableNotice(rows: SecurityNotice[]): SecurityNotice | null {
  const unread = rows.filter((r) => r.type_key === REBOUND_TYPE_KEY && r.read_at === null);
  if (unread.length === 0) return null;
  return [...unread].sort((a, b) => (a.created_at < b.created_at ? 1 : a.created_at > b.created_at ? -1 : 0))[0];
}

/** Actions are keyed on the type, never on the text. */
export function actionsFor(typeKey: string): NoticeAction[] {
  return typeKey === REBOUND_TYPE_KEY ? ['sign_out_all', 'dismiss'] : ['dismiss'];
}

/** A missing migration is "no notices"; anything else is a quiet failure retried on the next foreground. */
export function isMissingRpc(err: { code?: string | null; message?: string | null } | null | undefined): boolean {
  return !!err && (err.code === 'PGRST202' || /could not find the function/i.test(err.message ?? ''));
}
