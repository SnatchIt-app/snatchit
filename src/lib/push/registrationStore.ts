/**
 * src/lib/push/registrationStore.ts — the last registration and the last
 * failure, kept on the device so backoff survives a restart. Holds NO secret.
 */

import AsyncStorage from '@react-native-async-storage/async-storage';

import type { RegistrationFailure, RegistrationRecord } from './registration';

export const REGISTRATION_STATE_KEY = 'snatchit.push.registration.v1';

export interface RegistrationState {
  record: RegistrationRecord | null;
  failure: RegistrationFailure | null;
}

export const EMPTY_REGISTRATION_STATE: RegistrationState = { record: null, failure: null };

export interface KeyValueStore {
  getItem(key: string): Promise<string | null>;
  setItem(key: string, value: string): Promise<void>;
}

export async function loadRegistrationState(store: KeyValueStore = AsyncStorage): Promise<RegistrationState> {
  try {
    const raw = await store.getItem(REGISTRATION_STATE_KEY);
    if (!raw) return EMPTY_REGISTRATION_STATE;
    const parsed = JSON.parse(raw) as Partial<RegistrationState>;
    return { record: parsed.record ?? null, failure: parsed.failure ?? null };
  } catch {
    return EMPTY_REGISTRATION_STATE;
  }
}

export async function saveRegistrationState(state: RegistrationState, store: KeyValueStore = AsyncStorage): Promise<void> {
  try {
    await store.setItem(REGISTRATION_STATE_KEY, JSON.stringify(state));
  } catch {
    // Best effort: a lost record means one extra registration next time.
  }
}
