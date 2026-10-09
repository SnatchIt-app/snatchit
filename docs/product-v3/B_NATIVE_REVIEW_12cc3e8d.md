# B — native review of the final profile batch at `12cc3e8d`

Commits under review, in order:

| commit | what it is | B's classification |
|---|---|---|
| `2181de75` | `TRUST_NO_RATE` gets `completed_sales: 0` and consistent sibling counts | **P-4, fixture correction.** Unchanged from `B_CLASSIFICATION_P3_P4.md`; the owner has confirmed it. No screen change. |
| `9a564cc5` | hero blurb `numberOfLines={stackRows ? undefined : 2}` | **P-3, reachable product defect, minor.** Fix is correct as far as it goes. |
| `12cc3e8d` | the hero stacks above `identityStacks(fontScale)` | the readability fix the owner authorised. Reviewed below. |

Served from `snatchit-refund` at `12cc3e8d` through the repaired `dev-web-guard`
(`app_env=sandbox`, `pk_test`, process cwd read back from the kernel), device
`SN V3 393x852` / iOS 26.5. Captures `native/12cc3e8d/`, B-operated, every frame banner-gated.
No production call, reservation, payment, fixture write or authenticated session.

## 1. The default layout is not merely preserved — it is identical paint

`profile-default-{light,dark}-Boperated.png` at `12cc3e8d` against C's
`profile-default-{light,dark}-Coperated.png` at `857e6d93`, per-pixel, below the fixed header:

```
Light: differing pixels below y=440px: 0     (whole frame 2031, topmost at y=69px — the clock)
Dark : differing pixels below y=440px: 0     (whole frame 2192, topmost at y=69px — the clock)
```

**Zero.** Three commits — the fixture correction, the unclamp and the stacking — change nothing
the default size paints. The only differences anywhere in the frame are the status-bar clock and
battery. This is a stronger statement than "looks unchanged" and it is the one the owner asked
for ("confirm the default layout").

The default hero still reads, in both appearances: `TRANSFER SUCCESS RATE` / `100%` on the left;
`Trusted seller` and `14 sales · 100% transfer success` right-aligned on two lines, complete.

## 2. The stacked hero paints correctly — 3XL, both appearances

3XL (`extra-extra-extra-large`) is above `IDENTITY_STACK_SCALE = 1.3`, so it exercises the same
stacked branch as A3XL, and at that size the whole hero sits above the fold.

`profile-3xl-{light,dark}-hero-Boperated.png` show:

- `TRANSFER SUCCESS RATE` **on one line, unbroken**. The mid-word break I found at `857e6d93`
  (`TRANSFE` / `R` / `SUCCESS` / `RATE`, both appearances) is gone.
- `100%` whole, one line.
- The `Trusted seller` badge below the rate, left-aligned.
- `14 sales · 100% transfer success` **complete, on one line, left-aligned**, reading from the
  margin — not clamped, not wrapped inside a 150 pt column.
- The trust rows stacked beneath: `Completed sales / 14`, `Completed purchases / 3`,
  `Active listings / 2`.

### My review point on `heroLeft: { flex: 1 }` is answered by paint, not by argument
I flagged before the capture that `heroLeft` keeps `flex: 1`, which bounds the **width** in the
row form and the **height** in the column form (`flexGrow 1 / flexShrink 1 / flexBasis 0` inside
an auto-height parent is a known way to collapse a block in Yoga), and that `heroStacked` does not
neutralise it. **It does not collapse.** The rate block renders at full height in both 3XL frames.
I am recording the risk as not realised at 3XL rather than as never present; if the A3XL frames
show it, the partner style is `heroLeftStacked: { flex: 0, alignSelf: 'stretch' }`.

## 3. Gutter measurement — every B frame at `12cc3e8d`
Same instrument and the same four thresholds as `B_NATIVE_REVIEW_857e6d93.md`. Content edge
377 pt = x 1131 px; right gutter x ∈ [1131, 1178].

| frame | content ink in the gutter | max ink x |
|---|---|---|
| `profile-default-light` | 0 | 376.3 – 376.7 pt |
| `profile-default-dark` | 0 | 376.3 – 376.7 pt |
| `profile-3xl-light-hero` | 0 | 363.3 – 376.7 pt |
| `profile-3xl-dark-hero` | 0 | 363.3 – 376.7 pt |
| `profile-a3xl-light-top` | 0 | 361.3 pt |
| `profile-a3xl-dark-top` | 0 | 361.3 pt |

The only gutter signal in the A3XL frames is the same **144 px full-bleed header hairline**
identified at `857e6d93` — y 184.3–185.0 pt, 1179/1179 columns, contiguous — excluded by shape,
not by moving a threshold.

## 4. What is NOT covered, stated as a gap and not papered over
**The A3XL stacked hero is not captured.** It sits below the fold and B has no touch injection:
every mobile simulator action in this session, `attach` included, is refused with

> Mobile simulator tools require an attended session. They are not available in scheduled-task or
> remotely dispatched sessions.

`simctl` injects no touch either. Driving the Simulator through System Events would take the
foreground from whatever the owner is using, so it was not done unasked. The A3XL hero in Light
and Dark is requested from C, who has the capability; Metro was left running on 8081 out of
`snatchit-refund` at `12cc3e8d` for exactly that.

**3XL is not a substitute for A3XL.** It proves the stacked branch paints and that the blurb and
the label fit on one line at that scale. At A3XL the same text is roughly 2.3× larger again and
will wrap; whether it wraps on whole words is the question the owner asked and it is still open.
When C's frames land I measure gutter ink, max ink x against 377 pt, whether `TRANSFER` still
breaks, and whether the rate block collapsed.

## 5. Method corrections from this window, recorded because they void evidence
1. **`simctl ui appearance` does not drive this app.** The harness sets the theme from the app's
   stored preference, so the route needs `?appearance=light|dark`. My first A3XL frame came back
   Dark while `simctl` reported `appearance=light`; discarded and recaptured.
2. **`content_size` can revert across the dev-client relaunch** — set `extra-extra-extra-large`,
   read it back correctly, relaunch, and it reads `accessibility-extra-extra-extra-large`.
   Observed on 3 of 5 attempts. `shot.sh` reads the size back only *after* the capture, so a frame
   can be written under the wrong label. My capture is now gated on three readbacks and voids the
   frame without writing it.
3. **A correction to my own working.** I first said the two mislabelled frames were
   "byte-identical" to the A3XL pair. They were not — I had compared a float32 sum of a cropped
   band, which saturates and collides, instead of the md5 I had used correctly on C's nine frames
   an hour earlier. The frames were distinct; the failed size readback alone was the reason to
   discard them. Identity claims are md5.

## 6. Scope
This covers the profile batch and nothing else. It is **not** whole-app acceptance. The Listing
poster check is **not** repeated — the owner ruled the earlier default-size recheck complete and
these commits touch `app/profile/[id].tsx` and `app/_dev/v3-profile.tsx` only. Authenticated
consumer Home, the Edit refusal group and spoken VoiceOver remain explicitly untested.

---

# Addendum, same day — the A3XL gap is closed, and three corrections of mine

## 7. P-3 is CLOSED at `12cc3e8d`. A3XL, both appearances, measured and read.
C captured the stacked hero at A3XL at 19:14–19:15, after my last device use at 19:12:59. Copies
in `native/12cc3e8d/*Coperated.png`; C's copies in the app repo are the originals.

| frame | content ink in the gutter | max ink x |
|---|---|---|
| `profile-a3xl-light-hero-Coperated` | 0 | 361.3 pt |
| `profile-a3xl-light-blurb-Coperated` | 0 | 348.0 pt |
| `profile-a3xl-dark-hero-Coperated` | 0 | 348.0 pt |

Only the 144 px header hairline appears in the gutter, as everywhere else. All three md5-distinct;
header hairline at 553 px confirms A3XL from paint rather than from a readback.

**What the frames read, Light and Dark:**

```
TRANSFER                 <- whole words. At 857e6d93 this was  TRANSFE / R / SUCCESS / RATE
SUCCESS RATE
100%                     <- one line, whole
[Trusted seller]         <- badge below the rate, left-aligned
14 sales · 100%          <- complete, three lines, EVERY BREAK ON A WHOLE WORD,
transfer                    left-aligned from the margin.  At 857e6d93: "14 / sale…"
success
```

- **The mid-word break on `TRANSFER` is gone** in both appearances.
- **The blurb is complete and wraps on whole words.** This is the question the owner posed —
  complete text is not enough if the layout makes it hard to read — and the answer at A3XL is that
  the stacked form satisfies both.
- **The rate block does not collapse.** The `flex: 1` on `heroLeft` that I flagged is not realised
  as a defect at 3XL or at A3XL. The risk is recorded as not realised, not as never present.

**Verdict: P-1, P-2 and P-3 are closed at `12cc3e8d`; P-4 remains a fixture correction
(`2181de75`), and the default layout is byte-identical below the header.** This is the profile
batch only. It is not whole-app acceptance.

## 8. Correction — the device overlap was mine
C's log at `6d54d10f` said the window was B's and C's session was idle when I began, but C resumed
and **I did not re-check before using the device**. We were both on
`52282259-961E-4A1A-B32B-CEFA858CFF48` between roughly 18:56 and 19:04. C saw the content size
change underneath it and discarded frames because of me. I accept the rule E recorded: **one
operator at a time, declared before use.** My last device use was 19:12:59 and I have issued no
`simctl` since.

## 9. Correction — my "content_size reverts across the relaunch" finding is withdrawn
I recorded it as a simulator behaviour. C was setting A3XL on the same device in the same minutes,
and A3XL is exactly the value my readbacks reverted to. **A second operator is a sufficient
explanation and I cannot separate the two from this window.** The three-point size gate stays —
it voided every affected frame instead of writing it — but the diagnosis was wrong. Trap 1
(`simctl ui appearance` does not drive this app, because the harness reads the stored preference)
is unaffected and stands.

## 10. Correction — the identity question is settled, and against my earlier claim
E's record shows that every message E receives from B carries sender metadata
`from="local_228f989e-3ff8-449f-9e2b-823cf93637e1"`, `name="Claude B AWS/PFA-18C"` — and that the
round-trip phrase **`COPPER-LANTERN-377`**, which I invented in that message and which no other
party could have supplied, arrived under exactly that identity.

**So "Claude B AWS/PFA-18C" is this session.** My earlier explanation — that E's relays failed
because they were addressed to a *different* B — is **wrong and withdrawn**. E's messages were
addressed correctly the whole time.

The real cause is in E's recorded refusal, verbatim:

> `Not delivered to Claude Desktop session local_228f989e-3ff8-449f-9e2b-823cf93637e1: Message not delivered: session local_228f989e-3ff8-449f-9e2b-823cf93637e1 cannot receive messages (a remote orchestrator runs it, or nobody opened it); messages can't be delivered there. (delivery: undelivered; message_id: a7f16e0b-597d-48ca-a0c7-3787c48f9be6)`

**B → E is verified; E → B cannot deliver.** The channel is one-way and is not to be marked
bidirectional. `V3_ACCEPTANCE_RECORD.md` is the E → B channel and I will read it rather than wait
for messages. Neither side retries, and no restart is claimed as a fix — it is an untested step.

One further delivery fact for the record: my first send to C was refused with
`"The project folder at \"/Volumes/DEV-SSD/01_SNATCH_IT/repos/snatchit-refund\" no longer exists.
It may have been moved, deleted, or unmounted."` That is false — the volume was mounted
(`/dev/disk7s1`, 931 GiB, 7 % used), the folder existed, C's frames were readable, and I was
serving Metro out of it at the time. One retry succeeded. The error text is recorded because it is
a false negative about a path, not a filesystem fact.

## 11. E's badge-size question, answered — new finding **P-5**, not a blocker for this batch

**Measured** on `profile-a3xl-dark-hero-Coperated.png` (A3XL):

| element | painted ink height | relative to the blurb beside it |
|---|---|---|
| `Trusted seller` badge label | **16.3 pt** | **0.47×** |
| blurb `14 sales · 100% …` | 35.0 pt | 1.00× |
| `TRANSFER SUCCESS RATE` | 26.7 pt | 0.76× |
| `100%` | 86.0 pt | 2.46× |

The pill itself is 114 × 20.3 pt and does not grow.

**Mechanism, confirmed in source.** `src/components/ui/Badge.tsx:74` renders the label with
`maxFontSizeMultiplier={MAX_DISPLAY_FONT_SCALE}` and `numberOfLines={1}`.
`MAX_DISPLAY_FONT_SCALE = 1.3`. At A3XL the surrounding text is at roughly 3.1×, so the badge is
pinned at 1.3/3.1 ≈ 0.42 of it — which is what the paint shows. E saw this correctly.

**Is the information lost?** Only in one tier, and it is the adverse one. Checking every branch of
`deriveReputation`:

| tier | badge label (capped) | blurb (scales fully) | blurb carries the label? |
|---|---|---|---|
| new seller, 0 sales | New seller | No completed transfers yet | yes |
| new seller, <5 | New seller | N of 5 sales toward Trusted | yes |
| unrated | Unrated | N sales · transfer success unavailable | yes |
| trusted / top / elite | Trusted / Top / Elite seller | N sales · P% transfer success | **no** — the tier word appears only on the badge |
| needs review, disputes | Needs review | N lost disputes · P% success | partly — "lost disputes" implies it |
| **needs review, low rate** | **Needs review** | **P% transfer success** | **NO** |

In the last row the only thing that says *needs review* is the capped badge, supported by a
`warning`/`danger` tone — and colour alone is not an accessible carrier. **So at the largest text
size the single adverse signal on the panel is the smallest text on the panel.**

**Judgement.** Readable, but not acceptable as an accessibility answer at A3XL, for the same reason
the owner already ruled on the price: *a complete value is necessary, but capping it at 1.3× is not
automatically an acceptable accessibility solution.* Same mechanism, applied to a status word.

**Not a blocker for `12cc3e8d`, and I am not changing it here.**
- It is **pre-existing**: the cap is in `Badge`, not in anything this batch touched. `12cc3e8d` did
  not introduce it and does not make it worse.
- `Badge` is **shared** — the identity block's "Verified seller" and other screens use it — so
  changing the cap has blast radius well beyond this review. That is an owner/C decision.

**Recommendation, smaller option first:**
1. Carry the tier word in the blurb for the three positive tiers and the low-rate `needs_review`
   (`src/lib/profile/reputation.ts`). One line per branch, no shared-component blast radius, and
   the scaling line then carries the meaning.
2. The real fix is for the badge to scale with Dynamic Type — drop the cap, let the pill wrap or
   grow — which belongs to whoever owns `Badge` and needs its own sweep of every call site.

Filed as **P-5** for the owner and C. Evidence is the frame and the source line, both named above.
