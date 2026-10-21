/**
 * src/hooks/useListingDraft.ts — autosave the sell form and offer it back (CFT-608, item 36).
 *
 * On mount (signed in, enabled) it reads the account's draft. A draft becomes an OFFER — the
 * Sell tab shows ContinueListingBanner — and while the offer is undecided autosave waits, so
 * nothing the seller has not yet seen is overwritten. Continue hands the stored fields to
 * `onRestore`; Discard removes the draft; `clear()` removes it after a publish the server confirmed —
 * but only the draft this form has been writing: an older one still on offer is a different listing
 * that nobody chose to discard, so it stays, with its banner.
 *
 * The offer and the phase belong to the account they were read for. Under any other account they
 * read as nothing, so a change of account never shows, restores or autosaves over the last one's.
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
  accept: () => void;
  discard: () => void;
  /** Remove the draft this form wrote — only after the server confirmed the publish. An undecided offer stays. */
  clear: () => void;
}

type Phase = 'off' | 'loading' | 'offer' | 'editing';

export function useListingDraft({ userId, enabled, fields, onRestore }: UseListingDraftOptions): UseListingDraftReturn {
  const uid = enabled && userId ? userId : null;
  const [held, setHeld] = useState<{ uid: string; phase: Phase; offer: ListingDraftOffer | null } | null>(null);
  const mine = held !== null && held.uid === uid ? held : null;
  const phase: Phase = mine ? mine.phase : 'off';
  const offer = mine ? mine.offer : null;
  const [saver] = useState(() => createDraftAutosaver((u, f) => listingDraftStore.save(u, f)));
  const live = useRef(0);

  // Read this account's draft. A change of account (or unmount) drops anything pending for the last.
  useEffect(() => {
    if (!uid) {
      setHeld(null);
      return;
    }
    armListingDraftPurge();
    const run = ++live.current;
    setHeld({ uid, phase: 'loading', offer: null });
    void (async () => {
      const draft = await listingDraftStore.load(uid);
      const next = draft ? await prepareListingDraftOffer(draft, probeLocalImage) : null;
      if (run !== live.current) return;
      setHeld({ uid, phase: next ? 'offer' : 'editing', offer: next });
    })();
    return () => {
      live.current += 1;
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
    const restored = offer.fields;
    setHeld({ uid, phase: 'editing', offer: null });
    onRestore(restored);
  }, [uid, offer, onRestore]);

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
    // on offer (or still being read), it is a different listing, and only Discard may remove it.
    if (phase !== 'editing') return;
    void listingDraftStore.clear(uid);
  }, [uid, phase, saver]);

  return { offer, accept, discard, clear };
}
