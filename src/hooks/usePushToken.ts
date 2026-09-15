/**
 * src/hooks/usePushToken.ts — register this device's Expo push token for the
 * signed-in account. Call once at the app root.
 *
 * Build 16 behaviour (select, touch or insert, stop on conflict) is kept as the
 * LEGACY path and is the live path on every database today. The RPC path
 * (migration 128, A-08d) is tried first and falls back on PGRST202. The
 * decision of whether and how to register is pure (registration.ts), the
 * device secret's lifecycle is pure (deviceSecret.ts), and the network is
 * injected (registerToken.ts), so everything but the Expo calls is tested.
 *
 * Lifecycle: registers on sign-in and on every account change (a rebind, by
 * design); refreshes daily; retries with backoff on the next foreground after
 * a transient failure; stops on the terminal failures (the token is bound to
 * another account; a deterministic precondition refusal) until the account,
 * the token or the method changes. A lost device secret is recovered by
 * deleting the row this device owns and registering afresh, under the gates in
 * registerToken.ts. Sign-out is elsewhere (signOutEverywhere) and unchanged.
 * The 128 contract is not frozen (A, f7b31ad); a further delta is expected.
 *
 * - Skips silently on simulators / emulators (push tokens require real devices)
 * - Never throws — all errors are caught, classified and recorded
 * - Never logs the token's secret; the token itself is not logged either
 */
import { useEffect, useRef, useState } from 'react';
import { AppState, Platform } from 'react-native';
import * as Notifications from 'expo-notifications';
import * as Device from 'expo-device';
import Constants from 'expo-constants';

import { deviceRandomBytes } from '@/src/lib/randomness';
import { getOrCreateDeviceSecret } from '@/src/lib/push/deviceSecret';
import { secureSecretStore } from '@/src/lib/push/deviceSecretStore';
import { setRegisteredPushToken } from '@/src/lib/push/registeredToken';
import {
  decideRegistration,
  recordFailure,
  type RegistrationMethod,
  type RegistrationRecord,
} from '@/src/lib/push/registration';
import { registerLegacy, registerRpcWithRecovery, supabaseRegisterDeps, type PushPlatform } from '@/src/lib/push/registerToken';
import { loadRegistrationState, saveRegistrationState } from '@/src/lib/push/registrationStore';
import { publishRegistrationStatus } from '@/src/lib/push/registrationStatus';

type PushTokenResult = {
  pushToken:         string | null;
  permissionGranted: boolean;
};

/** Known for the life of the process: probed by the first RPC attempt. */
let rpcAvailable: boolean | undefined;
/** The first decision of this process registers regardless of the daily TTL (A's v2 clause). */
let coldLaunchPending = true;

export function usePushToken(userId: string | undefined): PushTokenResult {
  const [pushToken, setPushToken]                   = useState<string | null>(null);
  const [permissionGranted, setPermissionGranted]   = useState(false);
  const tokenRef = useRef<string | null>(null);
  const runningRef = useRef(false);
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    if (!userId) return;
    let alive = true;

    async function obtainToken(): Promise<string | null> {
      if (tokenRef.current) return tokenRef.current;
      // 1. Physical device check — push tokens don't work on simulators
      if (!Device.isDevice) {
        console.log('[usePushToken] Skipping — not a physical device');
        return null;
      }
      // 2. Request permission
      let { status } = await Notifications.getPermissionsAsync();
      if (status !== 'granted') {
        const res = await Notifications.requestPermissionsAsync();
        status = res.status;
      }
      if (status !== 'granted') {
        console.log('[usePushToken] Permission not granted');
        return null;
      }
      if (alive) setPermissionGranted(true);
      // 3. Android notification channel
      if (Platform.OS === 'android') {
        await Notifications.setNotificationChannelAsync('default', {
          name: 'Default',
          importance: Notifications.AndroidImportance.MAX,
          vibrationPattern: [0, 250, 250, 250],
        });
      }
      // 4. Get Expo push token
      const projectId = Constants.expoConfig?.extra?.eas?.projectId;
      const { data: token } = await Notifications.getExpoPushTokenAsync(projectId ? { projectId } : undefined);
      tokenRef.current = token;
      if (alive) setPushToken(token);
      // Remembered for sign-out, which deactivates this device's token (CFT-611).
      setRegisteredPushToken(token);
      return token;
    }

    async function attempt(): Promise<void> {
      if (runningRef.current || !userId) return;
      runningRef.current = true;
      try {
        const token = await obtainToken();
        if (!token) return;
        const uid = userId;
        const state = await loadRegistrationState();
        const decision = decideRegistration({
          userId: uid, token, record: state.record, failure: state.failure, rpcAvailable, now: Date.now(),
          coldLaunch: coldLaunchPending,
        });
        coldLaunchPending = false;
        if (decision.action === 'skip') {
          if (state.record && state.record.userId === uid && state.record.token === token) {
            publishRegistrationStatus({ state: 'registered', method: state.record.method, outcome: state.record.outcome, at: state.record.at });
          }
          return;
        }
        if (decision.action === 'wait') {
          publishRegistrationStatus({ state: 'waiting', kind: state.failure?.kind ?? 'unknown', retryAt: decision.retryAt ?? null });
          scheduleRetry(decision.retryAt);
          return;
        }

        const platform = Platform.OS as PushPlatform;
        const now = Date.now();
        let method: RegistrationMethod = decision.method;
        const previouslyRpcForThisBinding =
          state.record?.method === 'rpc' && state.record.token === token && state.record.userId === uid;
        let result = method === 'rpc'
          ? await tryRpc(token, platform, previouslyRpcForThisBinding)
          : await tryLegacy(uid, token, platform, now);

        // The one fallback: 128 is not deployed here. Insert-only legacy path.
        if (!result.ok && result.kind === 'rpc_missing') {
          rpcAvailable = false;
          method = 'legacy';
          result = await tryLegacy(uid, token, platform, now);
        } else if (method === 'rpc' && (result.ok || result.kind !== 'unknown')) {
          rpcAvailable = true;
        }

        if (result.ok) {
          const record: RegistrationRecord = {
            token, userId: uid, method: result.method, outcome: result.outcome, at: now,
            contractVersion: result.method === 'rpc' ? result.contractVersion : null,
          };
          await saveRegistrationState({ record, failure: null });
          publishRegistrationStatus({ state: 'registered', method: result.method, outcome: result.outcome, at: now });
          console.log('[usePushToken] Registered:', result.method, result.outcome);
          return;
        }

        const failure = recordFailure(state.failure, result.kind, { userId: uid, token, method, now });
        await saveRegistrationState({ record: state.record, failure });
        publishRegistrationStatus({ state: 'failed', kind: result.kind, at: now });
        console.warn('[usePushToken] Not registered:', result.kind);
        const next = decideRegistration({ userId: uid, token, record: state.record, failure, rpcAvailable, now });
        if (next.action === 'wait') scheduleRetry(next.retryAt);
      } catch (err) {
        console.warn('[usePushToken] Error:', err instanceof Error ? err.message : err);
      } finally {
        runningRef.current = false;
      }
    }

    async function tryRpc(token: string, platform: PushPlatform, previouslyRpcForThisBinding: boolean) {
      const secret = await getOrCreateDeviceSecret(secureSecretStore, deviceRandomBytes);
      if (!secret.ok) return { ok: false as const, kind: 'secret_unavailable' as const };
      const deviceName = Device.deviceName ?? Device.modelName ?? null;
      // `secret.created` is the ONLY signal of a lost secret: the server's
      // reply cannot reveal a mismatch. Recovery runs only under the gates.
      return registerRpcWithRecovery(
        supabaseRegisterDeps,
        { token, platform, secret: secret.secret, deviceName },
        { freshSecret: secret.created, previouslyRpcForThisBinding },
      );
    }

    function tryLegacy(uid: string, token: string, platform: PushPlatform, now: number) {
      return registerLegacy(supabaseRegisterDeps, { userId: uid, token, platform, nowIso: new Date(now).toISOString() });
    }

    // A short backoff retries in-process; anything longer waits for the next
    // foreground or sign-in, so a backgrounded app never wakes the radio.
    function scheduleRetry(retryAt?: number) {
      if (timerRef.current) { clearTimeout(timerRef.current); timerRef.current = null; }
      if (retryAt == null) return;
      const delay = retryAt - Date.now();
      if (delay <= 0 || delay > 10 * 60 * 1000) return;
      timerRef.current = setTimeout(() => { timerRef.current = null; void attempt(); }, delay);
    }

    void attempt();
    const sub = AppState.addEventListener('change', (st) => { if (st === 'active') void attempt(); });
    return () => {
      alive = false;
      sub.remove();
      if (timerRef.current) { clearTimeout(timerRef.current); timerRef.current = null; }
    };
  }, [userId]);

  return { pushToken, permissionGranted };
}
