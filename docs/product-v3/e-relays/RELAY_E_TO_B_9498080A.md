# E → B: focused review at `9498080a` after the migration (2026-10-09)

**Paths are now on the SSD.**
- Audit checkout: `/Volumes/DEV-SSD/01_SNATCH_IT/repos/snatchit-audit`.
- C's repo: `/Volumes/DEV-SSD/01_SNATCH_IT/repos/snatchit-refund`.
- Don't use the Mac originals.

**Window first.**
- C handed the simulator and Metro back to you at `9498080a` (`c11b4a49`).
- The migration then shut down the simulator and stopped all servers.
- **Agree ownership with C before either of you boots the device or starts Metro** (owner).
- The serving tree is at `2919ba75` (local-only): `c11b4a49` plus capture helpers in
  `tools/v3-capture/`, with no app code. Its modified `.claude/launch.json` is a documented
  migration change; leave it.

**Candidate code:** `9498080ab7eb15a064bc455bb3d4f06e48eceaf0`.
- Bid activity fix.
- Date/time wrap.
- Long-bid fixture.
- Profile rate fix and corrected fixture.

**Review C's 16 a3xl frames** (C-operated, banner-gated). They are in C's repo at
`native/9498080a/`, with `capture-log.txt`; C's handoff is `docs/product-v3/V3_BATCH8_HANDOFF.md`.
1. Bid activity, ordinary and four-figure, Light and Dark: every digit and the cents present.
2. Full date and time, Light and Dark.
3. **Home feature amount at a3xl**, ordinary and long. This is the check that was untested.
4. Profile: corrected and unknown rate.
5. C's account of the drag (3 of 4 scrolled; three automation faults with controls). Judge whether
   it holds.

**On the device, once the window is yours:** re-confirm the Listing poster clearance once at
default size, because `ListingHero` changed (date line only).

**Rule on these** (C recorded them, didn't fix them):
- Profile at a3xl: the trust % breaks mid-number ("10 / 0 / %"), trust-row values clip at the right
  edge, the badge blurb clamps, and one sub-line contradicts the sales count.

**Not yours to settle:**
- the proposed **"Unrated"** label (owner);
- C's claim that migration 031 makes the no-terminal-data shape unproducible (A/D).

**Still untested:**
- Edit refusals (signed-out guard).
- `?art=` on the six list harnesses.
- Signed-in Home.
- Spoken VoiceOver.

No whole-app acceptance.

Record: `V3_ACCEPTANCE_RECORD.md` at `498f3179`.
