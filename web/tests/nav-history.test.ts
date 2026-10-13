import { describe, expect, it } from "vitest";
import { nextStack } from "@/lib/nav-history";

describe("in-app history stack for the back chip", () => {
  it("pushes new pages and pops a step back", () => {
    let s = nextStack([], "/browse");
    s = nextStack(s, "/listing/a");
    expect(s).toEqual(["/browse", "/listing/a"]);
    s = nextStack(s, "/browse"); // history.back()
    expect(s).toEqual(["/browse"]);
  });
  it("a page opened directly has nothing behind it, even after visiting another and coming back", () => {
    let s = nextStack([], "/listing/a");
    s = nextStack(s, "/listing/b");
    s = nextStack(s, "/listing/a");
    expect(s).toEqual(["/listing/a"]); // the back chip now falls back to its href instead of leaving the site
  });
  it("ignores a repeat of the current page", () => {
    expect(nextStack(["/a", "/b"], "/b")).toEqual(["/a", "/b"]);
  });
});
