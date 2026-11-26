import { describe, expect, it, vi } from "vitest";
import { createSubmissionGuard } from "@/lib/events/submission";

describe("pending command submission", () => {
  it("allows one submit and refuses rapid click or implicit Enter repeats until settled", () => {
    const guard = createSubmissionGuard();
    const first = { preventDefault: vi.fn() };
    guard.onSubmit(first);
    expect(first.preventDefault).not.toHaveBeenCalled();
    for (let i = 0; i < 3; i++) {
      const repeat = { preventDefault: vi.fn() };
      guard.onSubmit(repeat);
      expect(repeat.preventDefault).toHaveBeenCalledOnce();
    }
    guard.release();
    const next = { preventDefault: vi.fn() };
    guard.onSubmit(next);
    expect(next.preventDefault).not.toHaveBeenCalled();
  });
});
