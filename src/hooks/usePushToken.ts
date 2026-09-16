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
 * registerToken.ts. Sign-out is elsewhere (signOutThisDevice / signOutAllDevices);
 * the hook only triggers the forced local re-auth on session_stale (131).
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
  beginChallenge, classifyChallengeError, isChallengeExpired, onBackground, onCodeEntered, onConfirmError, onConfirmOk,
  onFallbackDue, onForeground, onPushReceived, toCodeEntry, type ChallengeState,
} from '@/src/lib/push/challenge';
import { handleSessionStale } from '@/src/lib/push/sessionStale';
import { markSessionEnd } from '@/src/lib/auth/sessionEnd';
import { signOutThisDevice } from '@/src/lib/auth/signOut';
import {
  decideRegistration,
  recordFailure,
  type RegistrationMethod,
  type RegistrationRecord,
} from '@/src/lib/push/registration';
import { registerLegacy, registerRpcWithRecovery, supabaseRegisterDeps, type PushPlatform } from '@/src/lib/push/registerToken';
import { EMPTY_REGISTRATION_STATE, loadRegistrationState, saveRegistrationState } from '@/src/lib/push/registrationStore';
import { publishRegistrationStatus, setChallengeHandlers } from '@/src/lib/push/registrationStatus';

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
  // v3: the open proof-of-possession challenge for this device, if any. The
  // nonce never lives here: it is echoed the moment it arrives.
  const challengeRef = useRef<ChallengeState>({ phase: 'none' });
  const fallbackRef = useRef<ReturnType<typeof setTimeout> | null>(null);

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

        // v3: the token has history under another account — nothing is bound
        // until this device proves it holds the token. Keep the current record
        // (the server changed nothing), open the challenge, wait for the push.
        if (result.ok && result.method === 'rpc' && result.outcome === 'challenge_required') {
          const info = result.challenge ?? { id: '', mode: 'silent' as const, expires_in_s: 300 };
          if (!info.id) {
            publishRegistrationStatus({ state: 'failed', kind: 'unknown', at: now });
            return;
          }
          setChallenge(beginChallenge(info, now, AppState.currentState === 'active'), token);
          return;
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
        // 131 (provisional): this session can never register again — re-auth.
        if (result.kind === 'session_stale') {
          void handleSessionStale({
            clearRegistration: () => saveRegistrationState(EMPTY_REGISTRATION_STATE),
            markEnd: markSessionEnd,
            signOutLocal: async () => (await signOutThisDevice({ reason: 'credential_change' })).signedOut,
          });
          return;
        }
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

    // ── v3 challenge handling ──────────────────────────────────────────────
    function publishChallenge() {
      publishRegistrationStatus({ state: 'challenge', challenge: challengeRef.current, at: Date.now() });
    }

    function clearFallback() {
      if (fallbackRef.current) { clearTimeout(fallbackRef.current); fallbackRef.current = null; }
    }

    /** Arm the 60 s foreground fallback: no push by then → ask for the visible code. */
    function armFallback(token: string) {
      clearFallback();
      const st = challengeRef.current;
      if (st.phase !== 'awaiting_push' || !st.foreground) return;
      const delay = Math.max(0, CHALLENGE_FALLBACK_DELAY(st.startedAt));
      fallbackRef.current = setTimeout(() => {
        fallbackRef.current = null;
        if (!onFallbackDue(challengeRef.current, Date.now())) return;
        void requestVisibleCode(token);
      }, delay);
    }

    function CHALLENGE_FALLBACK_DELAY(startedAt: number): number {
      return startedAt + 60_000 - Date.now();
    }

    function setChallenge(next: ChallengeState, token: string) {
      challengeRef.current = next;
      publishChallenge();
      armFallback(token);
    }

    async function requestVisibleCode(token: string) {
      const st = challengeRef.current;
      if (st.phase !== 'awaiting_push') return;
      const secret = await getOrCreateDeviceSecret(secureSecretStore, deviceRandomBytes);
      if (!secret.ok) {
        challengeRef.current = { phase: 'failed', kind: 'unknown', challengeId: st.challengeId };
        publishChallenge();
        return;
      }
      const r = await supabaseRegisterDeps.requestChallenge(token, secret.secret);
      if (r.error) {
        challengeRef.current = onConfirmError({ phase: 'confirming', challengeId: st.challengeId, via: 'push' }, classifyChallengeError(r.error), null);
      } else {
        challengeRef.current = toCodeEntry(st);
      }
      publishChallenge();
    }

    /** Echo the nonce (silent) or the code (visible). The bind happens on the server here. */
    async function confirm(nonce: string, prior: Extract<ChallengeState, { phase: 'awaiting_code' }> | null, token: string, uid: string) {
      const st = challengeRef.current;
      if (st.phase !== 'confirming') return;
      clearFallback();
      const r = await supabaseRegisterDeps.confirmChallenge(st.challengeId, nonce);
      if (r.error) {
        challengeRef.current = onConfirmError(st, classifyChallengeError(r.error), prior);
        publishChallenge();
        return;
      }
      const d = r.data && typeof r.data === 'object' ? (r.data as Record<string, unknown>) : {};
      const tokenId = typeof d.token_id === 'string' ? d.token_id : null;
      challengeRef.current = onConfirmOk(st, tokenId);
      publishChallenge();
      const at = Date.now();
      const record: RegistrationRecord = { token, userId: uid, method: 'rpc', outcome: 'rebound', at, contractVersion: 3 };
      await saveRegistrationState({ record, failure: null });
      challengeRef.current = { phase: 'none' };
      publishRegistrationStatus({ state: 'registered', method: 'rpc', outcome: 'rebound', at });
      console.log('[usePushToken] Registered: rpc rebound (challenge confirmed)');
    }

    function handleNotification(data: unknown) {
      const r = onPushReceived(challengeRef.current, data);
      if (!r.nonce) return;
      challengeRef.current = r.state;
      publishChallenge();
      const token = tokenRef.current;
      if (token && userId) void confirm(r.nonce, null, token, userId);
    }

    async function submitCode(code: string) {
      const st = challengeRef.current;
      if (st.phase !== 'awaiting_code') return;
      if (isChallengeExpired(st, Date.now())) {
        challengeRef.current = { phase: 'failed', kind: 'expired', challengeId: st.challengeId };
        publishChallenge();
        return;
      }
      const r = onCodeEntered(st, code);
      if (!r.nonce) return;
      challengeRef.current = r.state;
      publishChallenge();
      const token = tokenRef.current;
      if (token && userId) await confirm(r.nonce, st, token, userId);
    }

    function retry() {
      clearFallback();
      challengeRef.current = { phase: 'none' };
      void attempt();
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

    setChallengeHandlers({ submitCode, retry });
    // v3: the silent challenge push is handled in the foreground only (no
    // background mode in this build); the payload is never logged.
    const notif = Notifications.addNotificationReceivedListener((n) => handleNotification(n.request.content.data));
    void attempt();
    const sub = AppState.addEventListener('change', (st) => {
      if (st === 'active') {
        const r = onForeground(challengeRef.current, Date.now());
        challengeRef.current = r.state;
        if (r.state.phase !== 'none') publishChallenge();
        const token = tokenRef.current;
        if (r.state.phase === 'awaiting_push' && token) armFallback(token);
        // Re-request the same open challenge (the server re-dispatches, no new nonce) or start over.
        void attempt();
        return;
      }
      if (st === 'background' || st === 'inactive') {
        challengeRef.current = onBackground(challengeRef.current);
        clearFallback();
      }
    });
    return () => {
      alive = false;
      sub.remove();
      notif.remove();
      clearFallback();
      setChallengeHandlers(null);
      if (timerRef.current) { clearTimeout(timerRef.current); timerRef.current = null; }
    };
  }, [userId]);

  return { pushToken, permissionGranted };
}
