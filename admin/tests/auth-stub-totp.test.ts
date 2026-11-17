import { spawnSync } from "node:child_process";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

/**
 * The local harness's MFA is only evidence if its TOTP is the real algorithm.
 * The stub's --selftest checks RFC 6238 Appendix B and RFC 4226 Appendix D
 * vectors, the base32 round trip and GoTrue's ±1-step window.
 */
describe("local auth stub TOTP", () => {
  it("passes the RFC 6238 / RFC 4226 self-test", () => {
    const r = spawnSync(process.execPath, [resolve(__dirname, "../scripts/auth-stub.mjs"), "--selftest"], { encoding: "utf8", env: { ...process.env, HARNESS_QR_ENCODER: "" } });
    expect(r.stdout).toMatch(/^SELFTEST OK totp=6 hotp=10/);
    expect(r.status).toBe(0);
  });
});
