# B's capture harnesses — preserved for the migration (2026-10-08)

Both sets are **method**, not evidence. Every capture they produced is already committed under
`docs/product-v3/native/`. Nothing irreplaceable was left in a temporary folder.

## `native/` — the iOS simulator capture helpers

Used for every native batch (`d5217530`, `91a5a58c`, `3c03778a`). They are shell wrappers around
`xcrun simctl`; they inject no touch input, which is why scroll checks were handed to C.

`ncap5.sh` is the current one and supersedes the rest; the earlier versions are kept because each
fixed a real method fault, in this order:

| file | what it added, and why |
|---|---|
| `ncap.sh` | bounce via `_dev/foundation` before the target — a second deep link to the **same** route does not re-read its params, which silently produced stale captures |
| `ncap2.sh` | cold start per capture. Abandoned: a cold start lands on Sign in, not the app |
| `ncap3.sh` | stability gate — two identical frame signatures before accepting |
| `ncap4.sh` | **asserts the sandbox banner is present.** Added after three captures turned out to be the Expo dev-client launcher, which is stable and colourful and passed the stability gate |
| `ncap5.sh` | relaxed the colour-count floor so sparse refusal screens are not rejected |

## `web/` — the react-native-web render harness

From the earlier web phase, against Metro on `:8083`. Superseded as evidence by the native path but
kept because the measurement methods are reused: `cdp-capture.mjs` (device metrics, appearance,
font-face probe), `batch-capture.mjs`, `scroll-capture.mjs`, `avatar-probe.mjs` (the avatar
measurement that closed that finding), `capture.sh`.

`seed-profile.mjs` reads `sandbox.env` and injects a session into a browser profile so authenticated
web screens could be reached **without typing a credential**. It contains **no secret values** —
it reads them at run time and never prints them. The browser profile it populated is **not** in this
folder; see the migration handoff.
