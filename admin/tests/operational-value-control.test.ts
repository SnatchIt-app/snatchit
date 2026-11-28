import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";
import { OperationalValueInput, resultBelongsToKey } from "@/components/system/OperationalSettingsForm";
import { specFor, type OperationalKeySpec } from "@/lib/operational-config";

vi.mock("server-only", () => ({}));
vi.mock("next/cache", () => ({ revalidatePath: vi.fn() }));
vi.mock("@/lib/ops", () => ({ callOps: vi.fn(), callKernelApproval: vi.fn() }));

const render = (spec: OperationalKeySpec) => renderToStaticMarkup(createElement(OperationalValueInput, { spec, id: "value-control" }));

describe("selected-key value control", () => {
  it("integer: number input with the int4 bound", () => {
    const html = render(specFor("inventory.per_user_active_hold_max")!);
    expect(html).toContain('type="number"');
    expect(html).toContain('min="1"');
    expect(html).toContain('max="2147483647"');
    expect(html).toContain('step="1"');
    expect(html).toContain('placeholder="6"');
    expect(html).toContain('name="value"');
    expect(html).toContain('required=""');
  });

  it("interval: text input with a unit example, no numeric max", () => {
    const html = render(specFor("inventory.hold_ttl_interval")!);
    expect(html).toContain('type="text"');
    expect(html).toContain('placeholder="10 minutes"');
    expect(html).toContain('name="value"');
    expect(html).toContain('required=""');
    expect(html).not.toContain('type="number"');
  });

  it("boolean: select with exactly true/false", () => {
    const html = render(specFor("feature.native_scanning_enabled")!);
    expect(html).toContain("<select");
    expect(html).toContain('name="value"');
    expect(html).toContain('value="true"');
    expect(html).toContain('value="false"');
    expect(html).toContain('required=""');
  });

  it("shows a result only for the key it belongs to", () => {
    expect(resultBelongsToKey("feature.native_scanning_enabled", "feature.native_scanning_enabled")).toBe(true);
    expect(resultBelongsToKey("feature.native_scanning_enabled", "inventory.hold_ttl_interval")).toBe(false);
    expect(resultBelongsToKey(undefined, "")).toBe(false);
  });

  it("renders a different control branch for each selected key (static branches; key-switch/reset interaction UNRUN)", () => {
    const integer = render(specFor("inventory.per_user_active_hold_max")!);
    const interval = render(specFor("inventory.hold_ttl_interval")!);
    const boolean = render(specFor("feature.native_issuance_enabled")!);
    expect(integer).not.toEqual(interval);
    expect(integer).not.toEqual(boolean);
    expect(interval).not.toEqual(boolean);
    // Static spec lookup only. The real key-switch/reset interaction is UNRUN; this does not prove browser state.
    expect(specFor("")).toBeNull();
  });
});
