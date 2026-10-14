"use client";

import { useId, useSyncExternalStore } from "react";
import {
  THEME_COOKIE,
  parseThemePreference,
  themeCookieString,
  type ThemePreference,
} from "@/lib/theme";

/**
 * Settings → Appearance, the web twin of native app/settings/appearance.tsx:
 * System (the default), Light, Dark as filled option rows with a radio at the
 * trailing edge — a control-coloured ring at rest, a red ring around a red dot
 * when chosen. Real radio inputs, so arrow keys move the choice and the group
 * is announced as one.
 *
 * The choice lives in the sn-theme cookie (src/lib/theme.ts), which the root
 * layout reads to render the right theme on the first byte. Choosing writes
 * the cookie and sets <html data-theme> so the page switches at once.
 */
const OPTIONS: { key: ThemePreference; label: string; description?: string }[] = [
  { key: "system", label: "System", description: "Follows your device" },
  { key: "light", label: "Light" },
  { key: "dark", label: "Dark" },
];

// The cookie is the store; this component is the only writer on the page.
const listeners = new Set<() => void>();

function subscribe(onChange: () => void) {
  listeners.add(onChange);
  return () => {
    listeners.delete(onChange);
  };
}

function readPreference(): ThemePreference {
  const prefix = `${THEME_COOKIE}=`;
  const entry = document.cookie.split("; ").find((c) => c.startsWith(prefix));
  return parseThemePreference(entry ? decodeURIComponent(entry.slice(prefix.length)) : null);
}

/** The server render (and hydration) shows no selection; the cookie is read once on the client. */
function serverPreference(): ThemePreference | null {
  return null;
}

function applyPreference(pref: ThemePreference) {
  document.cookie = themeCookieString(pref);
  document.documentElement.dataset.theme = pref;
  listeners.forEach((l) => l());
}

export function AppearanceSetting() {
  const preference = useSyncExternalStore<ThemePreference | null>(subscribe, readPreference, serverPreference);
  const name = useId();
  const legendId = `${name}-legend`;

  return (
    <fieldset role="radiogroup" aria-labelledby={legendId}>
      <legend id={legendId} className="t-title text-ink">
        Appearance
      </legend>
      <div className="mt-3 space-y-2">
        {OPTIONS.map((o) => {
          const checked = preference === o.key;
          const descId = o.description ? `${name}-${o.key}-desc` : undefined;
          return (
            <label
              key={o.key}
              className="pressable flex min-h-14 cursor-pointer items-center gap-3 rounded-panel bg-surface px-4 py-3 has-focus-visible:outline-2 has-focus-visible:outline-offset-2 has-focus-visible:outline-ink"
            >
              <input
                type="radio"
                name={name}
                value={o.key}
                checked={checked}
                onChange={() => applyPreference(o.key)}
                aria-describedby={descId}
                className="sr-only"
              />
              <span className="min-w-0 flex-1">
                <span className="t-title block text-ink">{o.label}</span>
                {o.description ? (
                  <span id={descId} className="t-body-sm mt-0.5 block text-muted">
                    {o.description}
                  </span>
                ) : null}
              </span>
              <span
                aria-hidden="true"
                className={`flex size-6 shrink-0 items-center justify-center rounded-full ${
                  checked ? "border-2 border-brand" : "border-[1.5px] border-control"
                }`}
              >
                {checked ? <span className="size-3 rounded-full bg-brand" /> : null}
              </span>
            </label>
          );
        })}
      </div>
    </fieldset>
  );
}
