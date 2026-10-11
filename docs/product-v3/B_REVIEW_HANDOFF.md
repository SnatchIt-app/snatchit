# B — review handoff

Independent visual review, Claude B. Everything below is B's own measurement and reading of frames
B did not capture, on device `SN V3 393x852` (iOS 26.5), 393 × 852 pt at 3× = 1179 × 2556 px,
16 pt gutters, **377 pt content edge**.

**This is not whole-app acceptance.** It is the set of items B has reviewed. Everything B has not
reviewed stays unreviewed; a pass here says nothing about any other screen.

Evidence classes are kept apart and never substitute for one another:
**source · web render · native simulator · physical device.** Nothing below is physical-device
evidence; there is none in this program.

---

## 1. PASSED ON PAINT
Measured and read on native frames. Each carries a **discrimination control** — a comparison that
would have failed if the fix had not landed — because a reading on its own is not falsifiable.

| Item | Served at | What the paint shows | Control |
|---|---|---|---|
| **P-1** rate broken across lines | `857e6d93` | `100%` whole on one line | `ratewrap` at `9498080a`: 2,597 px in the gutter at 392.7 pt → **0 px, 374.0 pt** |
| **P-2** trust-row values in the gutter | `857e6d93` | every value inside the content edge | `trustrows` at `9498080a`: 8,315 px at 392.7 pt → **0 px, 364.7–373.3 pt** |
| **P-3** badge blurb clamped | `12cc3e8d` | `14 sales · 100% / transfer / success` — complete, three lines, **every break on a whole word** | at `857e6d93` the same text read `14 / sale…` |
| **Hero word-break** `TRANSFE / R` | `12cc3e8d` | `TRANSFER / SUCCESS RATE` on whole words, both appearances | the break is present in both appearances at `857e6d93` |
| **Profile default layout** unchanged by the P-3/P-4/stacking batch | `12cc3e8d` vs `857e6d93` | **0 differing pixels below the fixed header**, both appearances | the two frames genuinely differ (2,031 / 2,192 px, all in the status-bar clock), so the zero is a real comparison |
| **W-4** header at A3XL | `1ab2c8e2` | `SETTINGS` / `APPEARANCE` whole, one line, shrunk to fit; hub and Appearance; Light and Dark | across the fix: **86,802 and 78,519 differing px, confined to y 23–163 pt** — the header band, nothing below it moved |
| **S-1 / S-1b** row labels | `1a6ac1c3` | `Notifications` whole on one line; `Edit profile` breaks on its space at full size; chevrons present; Light and Dark | at `e6a38aef` the same label reads `Notificatio / ns`; three attempts, three distinct md5s |
| **W-2** resale fee label | `2ada44bd` | `Service fee (10%)  $9.50` beside `Tickets $95.00` — the label describes arithmetic in the same frame | at `1ab2c8e2` the same row reads plain `Service fee  $9.50`: same amount, label only |
| **W-2b** sold note | `7d957100` | `Price includes the service fee.` with `SOLD FOR $132.00 total` untouched | the rate is present in the pre-change copy; amount unchanged either side |
| **P-5** information loss | `9bbeaec6` | blurb paints `Trusted seller · 14 sales · 100% transfer success` at full size | source checked on **every** `deriveReputation` branch, not just the fixture's |

**Gate applied to every frame before any of it was read:** sandbox banner present (so no frame is
the Expo dev-client launcher), md5-distinct, size read off the paint, and **zero content ink in the
right gutter** with max ink x inside 377 pt.

---

## 2. SOURCE-ONLY EVIDENCE — not visually verified, and not a pass
| Item | What is pinned in source | Why no frame exists |
|---|---|---|
| **W-6** payout copy, `payout-setup.tsx` | the sentence and its two guard tests (P-COPY1, P-COPY2) | it renders in the `connected` branch behind a server probe with **no fixture seam**. The kept frame is `not_connected` and proves only that that state is undisturbed |
| **W-5** Edit platform parity | test-pinned list parity | the picker is behind a session — see §3 |
| **P-4** no-rate fixture (`2181de75`) | `TRUST_NO_RATE` now sets `completed_sales: 0`; migration `031`'s superset relation makes the old 14/0 shape impossible from the RPC | a **fixture correction**, not a screen change: there is nothing new to photograph |

A source argument can be sound and still not be paint. On this screen alone, four things were
structurally sound and still needed a frame to settle them.

---

## 3. OWNER-WAIVED SIGN-IN CHECKS — **not passed, and not failures**
Repeat sign-in is waived by the owner. These are recorded as unreached, never as clean.

| Item | Exact blocker |
|---|---|
| **W-5** Edit platform picker | needs an authenticated session; the kept frame is `edit-picker-default-light-BLOCKED` |
| **W-6** payout `connected` state | needs an authenticated account **with Stripe connected** |
| **Authenticated consumer Home** | needs a session. B does not type the account password into the app |
| **Edit refusal group** (5 variants) | the signed-out guard renders first; all five produce a byte-identical signed-out screen |

**None of these may be marked passed on the strength of the waiver.** A waiver removes the
obligation to test; it does not supply a result.

---

## 4. OPTIONAL FOLLOW-UPS — not release blockers
| Item | State |
|---|---|
| **Spoken VoiceOver** | **optional per the owner, not a release blocker.** The exposed label is verified in source only; that is not a spoken result. No accessibility inspector is available here |
| **P-5, the `Badge` 1.3× cap itself** | open. `Badge.tsx:74` pins the label to `MAX_DISPLAY_FONT_SCALE` with `numberOfLines={1}`, so at A3XL it paints **16.3 pt against a 35.0 pt blurb — 0.47×**. The *information* loss is closed; the *legibility* one is not. `Badge` is shared, so the call is the owner's |
| **P-5 residual branch** | `reputation.ts:55`, `needs_review` from lost disputes, still does not name the tier (`N lost disputes · P% success`). **Unchanged, not regressed** — its blurb states the adverse fact |
| **One shared label/value row, or one test asserting no ink past 377 pt at A3XL** | proposed by B, agreed by C. The stacking rule has missed four surfaces: BidActivity → profile hero blurb → TrustRows → hero container |

---

## 5. OPEN — awaiting evidence, and **reclassified from my own earlier pass**
**W-4 at default size.** My review at `9bbeaec6` recorded W-4 as passing at *both* sizes. The A3XL
half stands on paint. **The default-size half does not, and I am withdrawing it from §1.**

The default frames in `native/1ab2c8e2/` are **byte-identical copies** of the `native/b64e5dd6/`
frames (md5 matches on `settings-hub-default-{light,dark}`, `appearance-default-light`,
`listing-breakdown-default-light`). C declares the copy in its capture log, so nothing is concealed.
But the claim resting on it — that a re-shoot after the fix differed by zero below y=440 — rests on
a frame that was **not kept**, so it cannot be checked. The same applies to the `e6a38aef` and
`1a6ac1c3` default claims.

The owner has ruled that no historical zero-difference comparison may be claimed from copied
baseline images or an unretained frame. **B has asked C for four fresh re-shot frames** —
`settings-hub-default-{light,dark}`, `appearance-default-{light,dark}` — at the commit actually
served, with the served sha read by `git rev-parse` in the capture window and used as the directory
name, the banner gate, `content_size` read on **both** sides of each frame, appearance driven by the
`?appearance=` route parameter rather than `simctl`, and **every frame a claim rests on kept**.

I expect the claim to hold: `SettingsHeader` spreads `{adjustsFontSizeToFit, minimumFontScale}` only
when `identityStacks(fontScale)` is true, onto a `Text` that already carried `numberOfLines={1}`, so
below the threshold the rendered props are unchanged by construction. **Expecting it is not
evidence.** The line stays open until the frames exist.

---

## 6. Method, and the instruments
`docs/product-v3/harness/measure/` — `gutter.py`, `hairline.py`, `sweep.py`, `shot3.sh`, with the
six rules they encode. They are in the repo because B's 2026-09-26 native captures were lost to a
session scratchpad and the numbers were being used as evidence while the instrument lived nowhere.

The two measurements B commits to on any frame: **content ink inside the right 16 pt gutter**, and
**max ink x against the 377 pt content edge**. Ink is deviation from each frame's own modal
background, reported at four thresholds so a result can be seen to be threshold-robust rather than
threshold-chosen. The recurring 144 px is the full-bleed header hairline — 1179/1179 columns,
contiguous, across a 0.7 pt band — excluded **by shape**, never by raising a threshold until it
disappears.

---

## 7. Corrections of record — B's own, carried forward so they are not re-made
| Correction | What was wrong |
|---|---|
| Batch 7 `null%` reachability | B argued the shape was reachable with real data. Migration `031`'s superset relation makes it impossible. The rendered defect was real; the escalation was not |
| Batch 8 profile findings | B read C's capture log to line 40 and reported two findings where there were four |
| Session identity | B claimed "Claude B AWS/PFA-18C" was a different session. The round-trip phrase `COPPER-LANTERN-377` arrived at E under exactly that identity, so it is **this** session. E addressed its relays correctly all along; inbound delivery here is refused. **Closed — not to be reopened** |
| `content_size` "reverts across the relaunch" | recorded as a simulator behaviour; **withdrawn**. C was setting A3XL on the same device in the same minutes. Each of us was seeing the other's writes |
| "Byte-identical" frames | B compared a float32 sum over a cropped band, which saturates and collides, instead of md5. The frames were distinct; the failed size readback alone justified discarding them |
| Re-running C's default diff | B got zero across the whole frame, clock included, and briefly took it as confirmation. It was **a file compared with itself** |
| Frame count at `9bbeaec6` | B published 23 frames as "twenty-four". E's count was right |
| Device overlap | B used the device while C was capturing, after C's log had handed over but C had resumed. C discarded frames because of it. **One operator at a time, declared before use** |

---

## 8. Capability limits of this session, stated so no one plans around them
- **No touch injection.** Every mobile simulator action, `attach` included, is refused:
  *"Mobile simulator tools require an attended session."* `simctl` injects none either. Anything
  below the fold must be captured by C. Default size generally needs no scrolling, so B can shoot
  those if a handover is declared.
- **No inbound session messages.** B → peers delivers; peers → B does not.
  **`V3_ACCEPTANCE_RECORD.md` is the inbound channel** and B reads it.
- **No accessibility inspector**, hence no spoken VoiceOver result.

## 9. State at handoff
- Review branch `design/frontend-audit-20260917`, verified remote tip **`6b8080bd`** at the time of
  writing; B pushes only its own evidence files and does not stage E's record.
- `origin/v3/midnight-app` `9bbeaec6` and `origin/v3/consumer-batch2` `6b6b8f48` are both on the
  remote; every evidence commit cited here is reachable from a pushed ref.
- **Simulator and Metro: not held by B.** No booted device and nothing on `:8081` at the time of
  writing. B takes the device only after a declared handover and releases it afterwards.
- No Mac original has been read-modified or deleted. No merge to `main`. No deployment.
