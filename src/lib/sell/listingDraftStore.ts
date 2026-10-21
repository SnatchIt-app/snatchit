/**
 * src/lib/sell/listingDraftStore.ts — where the sell-form draft lives, and when it goes (CFT-608).
 *
 * ONE DRAFT PER ACCOUNT, under `snatchit.sell.draft.v1:<uid>` in AsyncStorage. A read returns only
 * the asking account's draft; what fails to parse, is another version, or is for an event date the
 * seller picked that has passed is removed on read. Every call is wrapped: a storage failure is "no draft", never a crash.
 * Plain AsyncStorage (not the encrypted session store) because a draft holds only listing text that
 * becomes public when listed, plus a reference to a cached artwork file — no PII (default put to the
 * owner; see src/lib/sell/listingDraft.ts for what is never written).
 *
 * PURGE — every sign-out, and any change of account, removes the other accounts' drafts. The store
 * hears of both through its OWN onAuthStateChange subscription (`arm`), so neither the A-gated
 * sign-out path (src/lib/auth/signOut.ts) nor the shared root layout carries a line for it.
 * A sign-out is the SIGNED_OUT event, which auth-js emits on every real removal of a session
 * (`_removeSession`). A null session on any other event is not one: auth-js 2.98 hands
 * INITIAL_SESSION a null session when the stored token has expired and the refresh cannot reach the
 * server, yet keeps the stored session — an offline launch an hour after the app was killed, the very
 * interruption a draft exists for. Then nothing is read or written, and nothing is deleted, until an
 * account is current again; if that account is a different one, the change of account purges.
 *
 * WHY THE LISTENER IS SYNCHRONOUS (Build 17, src/lib/auth/authStateHandler.ts): auth-js runs
 * signOut() inside its lock and awaits whatever every onAuthStateChange callback returns. A callback
 * that awaits — worse, one that calls getSession() — keeps the lock, and every later data request
 * hangs until the app is killed. So `handleAuthChange` takes the uid from the session argument it is
 * handed, records it synchronously, queues the purge with `void`, and returns undefined. The same
 * pattern as app/_layout.tsx's `void clearRecoveryPending(AsyncStorage)`.
 *
 * ORDER — every storage operation runs through one queue, so a save already under way when a
 * sign-out lands is purged after it, not raced by it. A save for an account that is not the signed-in
 * one (a debounce firing after sign-out, say) is refused outright.
 *
 * A REFUSED READ IS NOT "NO DRAFT" — `read` says which it is. The screen's account (useAuth) and the
 * store's last auth event can disagree for a moment; a reader that took a refusal for "nothing
 * stored" would autosave over, or clear, a draft it never offered. `subscribe` tells readers of every
 * auth change, after the store has taken the new account, so a refused reader can read again.
 */

import AsyncStorage from '@react-native-async-storage/async-storage';
import type { AuthChangeEvent, Session } from '@supabase/supabase-js';

import { supabase } from '@/src/lib/supabase';
import {
  isListingDraftEmpty,
  isListingDraftExpired,
  parseListingDraft,
  serializeListingDraft,
  type ListingDraft,
  type ListingDraftFields,
} from '@/src/lib/sell/listingDraft';

export const LISTING_DRAFT_KEY_PREFIX = 'snatchit.sell.draft.v1:';

export function listingDraftKey(uid: string): string {
  return `${LISTING_DRAFT_KEY_PREFIX}${uid}`;
}

/** The slice of AsyncStorage the store uses (injected in tests). */
export interface DraftStorage {
  getItem(key: string): Promise<string | null>;
  setItem(key: string, value: string): Promise<void>;
  removeItem(key: string): Promise<void>;
  getAllKeys(): Promise<readonly string[]>;
  multiRemove(keys: readonly string[]): Promise<void>;
}

/** The slice of the auth client `arm` needs. The real supabase-js client satisfies it. */
export interface DraftAuthSource {
  onAuthStateChange(callback: (event: AuthChangeEvent, session: Session | null) => void): unknown;
}

/** What a read found. `refused`: the account is not the store's current one, so nothing was read. */
export type ListingDraftRead =
  | { status: 'draft'; draft: ListingDraft }
  | { status: 'none' }
  | { status: 'refused' };

const NONE: ListingDraftRead = { status: 'none' };
const REFUSED: ListingDraftRead = { status: 'refused' };

export interface ListingDraftStore {
  /**
   * The account's draft, `none`, or `refused` when the account is not the current one (a sign-out or a
   * change of account, even one that lands while the read waits its turn). Corrupt, other-version and
   * expired drafts are removed and read as `none`; a storage failure is `none`.
   */
  read(uid: string): Promise<ListingDraftRead>;
  /** `read`, as the draft or null — a refusal and "nothing stored" both null. */
  load(uid: string): Promise<ListingDraft | null>;
  /** Writes (or, for an empty form, removes) the account's draft. False when refused or failed. */
  save(uid: string, fields: ListingDraftFields): Promise<boolean>;
  /** Removes the account's draft (discard, or a publish the server confirmed). */
  clear(uid: string): Promise<void>;
  /** The onAuthStateChange listener. Synchronous by contract — see the header. */
  handleAuthChange(event: AuthChangeEvent, session: Session | null): void;
  /** Subscribes `handleAuthChange` to the auth client once; later calls do nothing. */
  arm(auth: DraftAuthSource): void;
  /**
   * Calls `listener` after every auth change the store hears, once it has taken the new account and
   * queued any purge (so a read the listener starts runs after the purge). Synchronously, inside the
   * auth callback: a listener must not await or call the auth client. Returns the unsubscribe.
   */
  subscribe(listener: () => void): () => void;
  /** Resolves when every queued storage operation has finished (tests, diagnostics). */
  idle(): Promise<void>;
}

export function createListingDraftStore(
  storage: DraftStorage,
  opts: { now?: () => Date } = {},
): ListingDraftStore {
  const now = opts.now ?? (() => new Date());
  /** undefined: no auth event seen yet · null: signed out · string: the signed-in account. */
  let currentUid: string | null | undefined;
  let armed = false;
  let queue: Promise<unknown> = Promise.resolve();
  const listeners = new Set<() => void>();

  function serial<T>(op: () => Promise<T>, fallback: T): Promise<T> {
    const run = queue.then(op).catch(() => fallback);
    queue = run;
    return run;
  }

  /**
   * Before the first auth event a read or write is allowed (the uid comes from the caller's own
   * session); after it, only for the signed-in account. A sign-out makes this false for everyone.
   */
  const isCurrent = (uid: string) => !!uid && (currentUid === undefined || currentUid === uid);

  async function purgeAllExcept(keep: string | null): Promise<void> {
    const keepKey = keep ? listingDraftKey(keep) : null;
    const keys = await storage.getAllKeys();
    const doomed = keys.filter((k) => k.startsWith(LISTING_DRAFT_KEY_PREFIX) && k !== keepKey);
    if (doomed.length > 0) await storage.multiRemove(doomed);
  }

  // The onAuthStateChange listener. Synchronous: no await, no auth call, nothing returned.
  function handleAuthChange(event: AuthChangeEvent, session: Session | null): void {
    const uid = session?.user?.id ?? null;
    const previous = currentUid;
    currentUid = uid;
    if (event === 'SIGNED_OUT') {
      void serial(() => purgeAllExcept(null), undefined);
    } else if (uid !== null && previous !== uid) {
      void serial(() => purgeAllExcept(uid), undefined);
    }
    // A reader waiting on a refused read tries again now. A listener that throws is ignored: it must
    // never break the auth callback.
    for (const listener of [...listeners]) {
      try { listener(); } catch { /* ignored */ }
    }
  }

  function read(uid: string): Promise<ListingDraftRead> {
    if (!isCurrent(uid)) return Promise.resolve(REFUSED);
    return serial<ListingDraftRead>(async () => {
      // Checked inside the queue, and again at the end: a sign-out or a change of account that landed
      // while this read waited (or ran) means the draft is no longer the signed-in account's to see.
      if (!isCurrent(uid)) return REFUSED;
      const key = listingDraftKey(uid);
      const raw = await storage.getItem(key);
      let draft = raw === null ? null : parseListingDraft(raw);
      if (raw !== null && (!draft || isListingDraftExpired(draft, now()))) {
        await storage.removeItem(key);
        draft = null;
      }
      if (!isCurrent(uid)) return REFUSED;
      return draft ? { status: 'draft', draft } : NONE;
    }, NONE);
  }

  return {
    read,

    load(uid) {
      return read(uid).then((r) => (r.status === 'draft' ? r.draft : null));
    },

    save(uid, fields) {
      if (!isCurrent(uid)) return Promise.resolve(false);
      return serial(async () => {
        // Checked again inside the queue: a sign-out queued ahead of this write has already run.
        if (!isCurrent(uid)) return false;
        const key = listingDraftKey(uid);
        if (isListingDraftEmpty(fields)) await storage.removeItem(key);
        else await storage.setItem(key, serializeListingDraft(fields, now()));
        return true;
      }, false);
    },

    clear(uid) {
      if (!uid) return Promise.resolve();
      return serial(async () => { await storage.removeItem(listingDraftKey(uid)); }, undefined);
    },

    handleAuthChange,

    arm(auth) {
      if (armed) return;
      armed = true;
      // A block body: auth-js awaits the callback's return value, and this one returns nothing.
      auth.onAuthStateChange((event, session) => { handleAuthChange(event, session); });
    },

    subscribe(listener) {
      listeners.add(listener);
      return () => { listeners.delete(listener); };
    },

    idle() {
      return queue.then(() => undefined, () => undefined);
    },
  };
}

/** The app's store. */
export const listingDraftStore = createListingDraftStore(AsyncStorage);

/** Subscribes the app's store to the app's auth client. Idempotent; safe to call from any mount. */
export function armListingDraftPurge(auth: DraftAuthSource = supabase.auth): void {
  listingDraftStore.arm(auth);
}
