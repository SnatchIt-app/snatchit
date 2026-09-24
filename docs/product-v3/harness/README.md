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

## The two local modifications, disclosed and reproducible

`src/theme/appearance.tsx` in the render worktree only, **uncommitted and never merged**:
`Appearance.setColorScheme` does not exist in `react-native-web`, so `AppearanceProvider` throws and the app
boots straight into its error boundary. The harness guards the call with a `typeof === 'function'` check.

**This is also a real finding for C, at their discretion:** the app cannot run on the web target at all
without that guard. It is not an iOS defect — Build 24 runs on the phone.

### 2 · `src/theme/fonts.ts` — the brand fonts did not load on the Expo web target

Root-caused with `systematic-debugging`, not guessed. Evidence, in order:

1. `document.fonts` held **six registered faces, every one `status: "unloaded"`**, and
   `document.fonts.check('700 30px Oswald_700Bold')` was **false**.
2. The injected `@font-face` rules register **`Oswald_700Bold`, `Inter_400Regular`, …** — expo-font's
   suffixed names.
3. But every rendered element computed **`font-family: Oswald` / `Inter`** — unsuffixed.
4. Source: `fonts.ts:131` — `if (Platform.OS === 'web') return role === 'display' ? 'Oswald' : 'Inter';`

**Root cause:** that branch is correct for the **Next.js `web/` app**, which loads the faces under their
canonical names through its own CSS pipeline — the comment says exactly that. It is **wrong for the Expo web
target**, where expo-font registers the suffixed names. The requested family therefore matched no registered
face, so the browser never fetched one and fell back to **Times**.

**Harness fix:** that web branch returns `FAMILY[role]` — the same suffixed names the native path uses.

**Verified, not assumed:** after the change the faces report `loaded`, elements compute
`Oswald_700Bold` / `Inter_400Regular` / `Inter_500Medium` / `Inter_700Bold`, and
`comparisons/harness_fonts_before_after.png` shows the serif replaced by real condensed Oswald.
(`Inter_600SemiBold` stays `unloaded` on this screen because nothing there uses it — correct lazy loading.)

**Not an iOS defect.** On native, `fontFamily()` returns `FAMILY[role]` and expo-font loads the faces; the
phone build renders correct type. For C this is a low-priority latent inconsistency — `brandFontsActive()`
also returns `true` unconditionally on web — and it only matters if the Expo web target is ever used.

**Typography, wrapping, spacing and geometry comparisons are valid only with this fix applied.** Before it,
every such comparison was invalid, and I made none.

## The boundary — stated once

**Web rendering is development evidence. It is not iOS evidence.** These captures establish layout,
composition, spacing, component shape, colour roles, artwork and fallback treatment, copy and state
behaviour. They do **not** establish anything that depends on the native runtime, and I will not claim iOS
parity from them. Specifically **still requiring native capture**:

- **Native text rendering.** The bundled Oswald and Inter **do load and render in this harness** (verified —
  see modification 2), so family, case, size, weight and wrapping comparisons are valid here. What is still
  unverified is how the same faces **rasterise on iOS**: hinting, sub-pixel positioning, the real line-box
  metrics for condensed Oswald, and Dynamic Type. Those need a native capture.
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
