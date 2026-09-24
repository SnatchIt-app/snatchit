# B's V3 render harness — the real app, captured to disk

Built 2026-09-24 so visual QA runs on **rendered output**, not on source. It renders the **real application
components** through Expo's web target; nothing here is a recreated mock screen.

## What it is

| | |
|---|---|
| Worktree | `/Users/josetascon/snatchit-v3render`, detached at the commit under review (currently `404bce38`) |
| Dependencies | `node_modules` **cloned** (APFS `cp -Rc`) from C's worktree. **Not a symlink** — Metro resolves the entry through the project root, and a symlink makes it serve `entry.bundle` from an absolute path with a 404/JSON MIME error |
| Environment | `.env.local` written from `eas.json`'s **preview** profile → sandbox project only, `pk_test_` key. **Never production** |
| Server | `npx expo start --web --port 8083` (not CI mode, so edits rebuild) |
| Capture | `capture.sh <out-dir> <route> <name>` → headless system Chrome at **393×852 logical, ×3** = **1179×2556**, the same geometry as the owner's Build 24 screenshots |

## The one local modification, disclosed

`src/theme/appearance.tsx` in the render worktree only, **uncommitted and never merged**:
`Appearance.setColorScheme` does not exist in `react-native-web`, so `AppearanceProvider` throws and the app
boots straight into its error boundary. The harness guards the call with a `typeof === 'function'` check.

**This is also a real finding for C, at their discretion:** the app cannot run on the web target at all
without that guard. It is not an iOS defect — Build 24 runs on the phone.

## The boundary — stated once

**Web rendering is development evidence. It is not iOS evidence.** These captures establish layout,
composition, spacing, component shape, colour roles, artwork and fallback treatment, copy and state
behaviour. They do **not** establish anything that depends on the native runtime, and I will not claim iOS
parity from them. Specifically **still requiring native capture**:

- Font rendering — **web falls back to a serif**; Oswald and Inter are not loaded here, so **no font family,
  weight, case or wrapping finding may be made from a web capture**.
- Safe-area insets, the real status bar, and the home indicator.
- Keyboard appearance and avoidance, and native dialogs / action sheets.
- Dynamic Type at the iOS accessibility sizes.
- `Appearance.setColorScheme` telling the OS about an explicit override.
- Native image decoding and the avatar's sized-URL behaviour.

## Signed-out routing

Every route redirects to `/(auth)/login` while signed out (`rootRouteDecision`), so the mapped consumer
screens need a session in the harness. **Signing in on web registers no push token** — the log shows
`[expo-notifications] Listening to push token changes is not yet fully supported on web` — so the harness
does not incur the DV-611 side effect that a device sign-in does.
