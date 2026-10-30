/**
 * src/lib/push/deviceSecretStore.ts — the Keychain / Keystore binding for the
 * device secret. Thin, so deviceSecret.ts stays pure.
 */

import * as SecureStore from 'expo-secure-store';

import type { SecretStore } from './deviceSecret';

export const secureSecretStore: SecretStore = {
  get: (key) => SecureStore.getItemAsync(key),
  set: (key, value) => SecureStore.setItemAsync(key, value),
};
