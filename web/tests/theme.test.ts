import { describe, expect, it } from "vitest";
import { THEME_COOKIE, parseThemePreference, themeCookieString } from "@/lib/theme";

describe("appearance preference", () => {
  it("accepts the three native choices", () => {
    expect(parseThemePreference("system")).toBe("system");
    expect(parseThemePreference("light")).toBe("light");
    expect(parseThemePreference("dark")).toBe("dark");
  });
  it("treats anything else as system", () => {
    for (const v of [undefined, null, "", "Dark", "auto", "constructor", "__proto__", "dark; Path=/"]) {
      expect(parseThemePreference(v as string | undefined)).toBe("system");
    }
  });
  it("writes a first-party, year-long cookie", () => {
    expect(themeCookieString("dark")).toBe(`${THEME_COOKIE}=dark; Path=/; Max-Age=31536000; SameSite=Lax`);
  });
});
