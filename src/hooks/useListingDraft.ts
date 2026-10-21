/**
 * src/hooks/useListingDraft.ts — autosave the sell form and offer it back (CFT-608, item 36).
 *
 * On mount (signed in, enabled) it reads the account's draft. A draft becomes an OFFER — the
 * Sell tab shows ContinueListingBanner — and while the offer is undecided autosave waits, so
 * nothing the seller has not yet seen is overwritten. It does not wait on a seller who is typing:
 * `formHasInput` turns true with their first input, and the banner then asks at once whether to start
 * a new listing (Discard, after which this form autosaves) or continue the saved one (review LD-R3). Continue hands the stored fields to
 * `onRestore`; Discard removes the draft; `clear()` removes it after a publish the server confirmed —
 * but only the draft this form has been writing: an older one still on offer is a different listing
 * that nobody chose to discard, so it stays, with its banner.
 *
 * The offer and the phase belong to the account they were read for. Under any other account they
 * read as nothing, so a change of account never shows, restores or autosaves over the last one's.
 *
 * A read the store REFUSES (this account is not the store's current one — the screen's useAuth and
 * the store's own auth listener can disagree for a moment) is not "no draft": the hook WAITS, with
 * autosave and `clear()` off, and reads again on the store's next auth change. Taking it for "nothing
 * stored" would let the next keystroke overwrite, or a confirmed publish remove, a draft never offered.
 * Otherwise every change is saved after AUTOSAVE_DELAY_MS of quiet, and at once when the app leaves
 * the foreground (the kill that a draft exists for). Unmounting — a sign-out unmounts the tabs —
 * cancels a pending write rather than flushing it; the store would refuse it anyway.
 *
 * `enabled: false` (the dev harness's `fixture`) makes the hook inert: no read, no write, no
 * auth subscription, no offer.
 *
 * The cover comes back only if the picker's cache file still answers `Image.getSize` within
 * COVER_PROBE_TIMEOUT_MS; otherwise it is dropped from what is restored and the banner says so.
 */

import { useCallback, useEffect, useRef, useState } from 'react';
import { AppState, Image } from 'react-native';

import {
  isListingDraftFieldsExpired,
  isListingDraftEmpty,
  listingDraftSignature,
  prepareListingDraftOffer,
  type ListingDraftFields,
  type ListingDraftOffer,
} from '@/src/lib/sell/listingDraft';
import { armListingDraftPurge, listingDraftStore } from '@/src/lib/sell/listingDraftStore';

export const AUTOSAVE_DELAY_MS = 1_000;
export const COVER_PROBE_TIMEOUT_MS = 3_000;

/** Does a local image still exist and decode? Never rejects; a timeout is "no". */
export function probeLocalImage(uri: string, timeoutMs: number = COVER_PROBE_TIMEOUT_MS): Promise<boolean> {
  return new Promise((resolve) => {
    let settled = false;
    const timer = setTimeout(() => finish(false), timeoutMs);
    function finish(there: boolean) {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve(there);
    }
    try {
      Image.getSize(uri, () => finish(true), () => finish(false));
    } catch {
      finish(false);
    }
  });
}

export interface DraftAutosaver {
  /** Write these fields after the quiet period; the same content again does not push it back. */
  schedule(uid: string, fields: ListingDraftFields): void;
  /** Write the pending fields now, if any. */
  flush(): Promise<void>;
  /** Drop the pending write and forget what was last written. */
  forget(): void;
}

export function createDraftAutosaver(
  write: (uid: string, fields: ListingDraftFields) => Promise<unknown>,
  delayMs: number = AUTOSAVE_DELAY_MS,
): DraftAutosaver {
  let timer: ReturnType<typeof setTimeout> | null = null;
  let pending: { uid: string; fields: ListingDraftFields; sig: string } | null = null;
  let lastSig: string | null = null;
  const stop = () => { if (timer !== null) { clearTimeout(timer); timer = null; } };
  const saver: DraftAutosaver = {
    schedule(uid, fields) {
      const sig = `${uid}\n${listingDraftSignature(fields)}`;
      if (pending ? pending.sig === sig : lastSig === sig) return;
      pending = { uid, fields, sig };
      stop();
      timer = setTimeout(() => { void saver.flush(); }, delayMs);
    },
    async flush() {
      stop();
      const p = pending;
      pending = null;
      if (!p) return;
      lastSig = p.sig;
      await write(p.uid, p.fields);
    },
    forget() {
      stop();
      pending = null;
      lastSig = null;
    },
  };
  return saver;
}

export interface UseListingDraftOptions {
  userId: string | null | undefined;
  /** False in the harness fixture mode: the hook does nothing at all. */
  enabled: boolean;
  /** The form as it stands. */
  fields: ListingDraftFields;
  /** Puts restored fields back into the form (Continue). */
  onRestore: (fields: ListingDraftFields) => void;
}

export interface UseListingDraftReturn {
  /** A stored draft waiting for Continue or Discard, or null. */
  offer: ListingDraftOffer | null;
  /**
   * The offer is up and the form already holds the seller's input (anything isListingDraftEmpty
   * counts). The banner asks which listing to keep rather than letting autosave sit paused.
   */
  formHasInput: boolean;
  accept: () => void;
  discard: () => void;
  /** Remove the draft this form wrote — only after the server confirmed the publish. An undecided offer stays. */
  clear: () => void;
}

type Phase = 'off' | 'loading' | 'waiting' | 'offer' | 'editing';

export function useListingDraft({ userId, enabled, fields, onRestore }: UseListingDraftOptions): UseListingDraftReturn {
  const uid = enabled && userId ? userId : null;
  const [held, setHeld] = useState<{ uid: string; phase: Phase; offer: ListingDraftOffer | null } | null>(null);
  const mine = held !== null && held.uid === uid ? held : null;
  const phase: Phase = mine ? mine.phase : 'off';
  const offer = mine ? mine.offer : null;
  const formHasInput = offer !== null && !isListingDraftEmpty(fields);
  const [saver] = useState(() => createDraftAutosaver((u, f) => listingDraftStore.save(u, f)));
  const live = useRef(0);

  // Read this account's draft; on a refusal, wait and read again on the store's next auth change.
  // A change of account (or unmount) drops anything pending for the last.
  useEffect(() => {
    if (!uid) {
      setHeld(null);
      return;
    }
    const id = uid;
    armListingDraftPurge();
    const run = ++live.current;
    let reading = false;
    let waiting = false;
    let missed = false;      // an auth change arrived while a read was under way
    setHeld({ uid: id, phase: 'loading', offer: null });
    const read = async (): Promise<void> => {
      reading = true;
      missed = false;
      const result = await listingDraftStore.read(id);
      const next = result.status === 'draft' ? await prepareListingDraftOffer(result.draft, probeLocalImage) : null;
      reading = false;
      if (run !== live.current) return;
      if (result.status === 'refused') {
        if (missed) { void read(); return; }
        waiting = true;
        setHeld({ uid: id, phase: 'waiting', offer: null });
        return;
      }
      setHeld({ uid: id, phase: next ? 'offer' : 'editing', offer: next });
    };
    // Called inside the store's synchronous auth listener: it only queues a read, never awaits.
    const unsubscribe = listingDraftStore.subscribe(() => {
      if (run !== live.current) return;
      if (reading) missed = true;
      else if (waiting) { waiting = false; void read(); }
    });
    void read();
    return () => {
      live.current += 1;
      unsubscribe();
      saver.forget();
    };
  }, [uid, saver]);

  // Autosave — only once the seller is editing (never over an undecided offer).
  useEffect(() => {
    if (!uid || phase !== 'editing') return;
    saver.schedule(uid, fields);
  }, [uid, phase, fields, saver]);

  // Leaving the foreground writes at once: an app kill gives no warning.
  useEffect(() => {
    if (!uid) return;
    const sub = AppState.addEventListener('change', (state) => {
      if (state !== 'active') void saver.flush();
    });
    return () => sub.remove();
  }, [uid, saver]);

  const accept = useCallback(() => {
    if (!uid || !offer) return;
    // An offer held open across midnight can name a picked event day that has since passed. Apply the
    // load-time rule again (isListingDraftExpired): such a draft is removed, not restored — so a past
    // event date can never reach the form through Continue (E, D-2.4 L1).
    if (isListingDraftFieldsExpired(offer.fields, new Date())) {
      saver.forget();
      setHeld({ uid, phase: 'editing', offer: null });
      void listingDraftStore.clear(uid);
      return;
    }
    const restored = offer.fields;
    setHeld({ uid, phase: 'editing', offer: null });
    onRestore(restored);
  }, [uid, offer, onRestore, saver]);

  const discard = useCallback(() => {
    if (!uid) return;
    saver.forget();
    setHeld({ uid, phase: 'editing', offer: null });
    void listingDraftStore.clear(uid);
  }, [uid, saver]);

  const clear = useCallback(() => {
    if (!uid) return;
    saver.forget();
    // Only once the seller is editing is the stored draft this form's own. While an older draft is
    // on offer (or still being read, or its read was refused), it is a different listing, and only
    // Discard may remove it.
    if (phase !== 'editing') return;
    void listingDraftStore.clear(uid);
  }, [uid, phase, saver]);

  return { offer, formHasInput, accept, discard, clear };
}
