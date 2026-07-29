# Snatch It brand system — measured from snatchitapp.com

Audited 2026-07-29 against the live rendered site (desktop 1280/800 viewport + 375 mobile),
cross-checked against `landing-v2/` drop-in source in this repo. Every value below was read
from computed styles or the site's own stylesheets — nothing estimated.

## 1. Typography

| Role | Face | Weight | Size | Tracking | Leading | Case | Color |
|---|---|---|---|---|---|---|---|
| Wordmark H1 | Oswald | 700 | 4.5rem → 16rem (xl) | −0.03em | 0.85 | uppercase | `#FF1A1A` + glow |
| Section H2 | Oswald | 700 | 30 → 60px | −0.02em | 0.95 | uppercase | white or red |
| Step/row head | Oswald | 700 | 20 → 48px | tracking-tight | 1.0–1.02 | uppercase | white (red variant) |
| Numerals 01–04 | Oswald | 700 | 96px desktop | −0.03em | 1.0 | — | `#FF1A1A` + subtle glow |
| Hero subline | Oswald | 700 | 16 → 24px | +0.3em | 1.33 | uppercase | white |
| FAQ summary | Oswald | 400 | 16px | normal | — | none | white |
| Body | Inter | 400 | 14 → 18px | normal | relaxed (1.5–1.625) | sentence | white/70 |
| Section eyebrow | Inter | 400 | 10 → 12px | **+0.5em** | — | uppercase | red/80 |
| Journal/meta line | Inter | 400 | 10 → 12px | +0.4em | — | uppercase | red/70 date · white/45 label |
| Nav & footer links | Inter | 400 | 10 → 12px | +0.3em | — | uppercase | white/60 → red hover |
| Primary CTA | Inter | **700** | 16 → 18px | +0.05em (`tracking-wider`) | — | uppercase | black on red |
| Microlines | Inter | 400 | 10px | +0.4–0.5em | — | uppercase | white/30–40 |

- Loading: `next/font/google` — Oswald weights 400/500/600/700 as `--font-oswald`
  (fallback `Impact, "Arial Black", sans-serif`), Inter variable 100–900 as body default.
  Self-hosted woff2 (`*-s.p.*.woff2` preloads). No CDN, no OS font stack.
- Voice: copy is written as sentences with periods ("The night, in writing.") and
  *rendered* uppercase by CSS. Body copy stays sentence case.
- Uppercase restraint: display type, labels, buttons only. Never on body text.

## 2. Color (site's own `:root` tokens)

```
--background #000        --foreground #fff
--card #0a0a0a           --secondary/--muted #111      --muted-foreground #666
--primary #ff1a1a        --primary-foreground #000     (black text on red)
--border #ff1a1a         --ring #ff1a1a                --radius 0
hover red: #CC0000
```

- White opacity ladder: /70 body · /60 links · /45 meta · /40 taglines · /30 microlines · /20 slashes · /10 image frames.
- Red opacity ladder: /80 eyebrows · /70 dates · /30 sticky-CTA hairline · /20 dividers · /15 section hairlines.
- **Hairlines are red-tinted** (`#FF1A1A` at 15–30%), not gray: section top borders /15,
  list dividers + subpage header /20, sticky CTA /30.

## 3. Geometry & surfaces

- `--radius: 0` — every button, input, badge, panel is square. The only rounding on the
  site is `rounded-[2rem]` on phone-hardware mockups (depicting the device, not UI).
- No boxed cards anywhere on marketing pages: lists are `border-y` + `divide-y` red hairline
  rows; journal entries are borderless `group` blocks whose titles turn red on hover.
- Two-column label grid `sm:grid-cols-[16rem_1fr]` for definition lists (Why Us, Trust).
- Section rhythm: `py-20` mobile → `py-28`/`py-40` desktop; heading blocks `mb-16–24`;
  content widths `max-w-3xl` (prose pages) / `max-w-5xl` (grids) / `max-w-6xl` (footer).
- Separator motifs: `/` slash (white/20) between uppercase meta tokens; `·` interpunct in
  running text and the footer copyright.

## 4. Imagery

- `/atmosphere/*.jpg` (crowd, club-line, silhouettes, sold-out, concert-lights): cinematic
  low-key crowd/venue photos used as section underlays — `bg-cover`, opacity **0.08–0.22**,
  paired with a black `mix-blend-multiply` layer. Images emerge from black; never bright.
- Hero adds: central red glow (`bg-[#FF1A1A]/15 blur-[180px]`), three thin diagonal
  red light-streaks (`h-[2px]` blurred, rotated), `.vignette-red` inset shadow.
- Global `.grain`: SVG fractal-noise overlay, opacity 0.03, z-100, over everything.
- App screenshots shown in white/10-bordered phone frames with `shadow-2xl`.

## 5. Components

- **Primary button**: square, `bg-#FF1A1A text-black font-bold uppercase tracking-wider`,
  `px-12 py-5` (hero) / full-width `py-4` (sticky), `.btn-glow`
  (`0 0 20px red/50, 0 0 40px red/30`), hover `#CC0000` + glow deepens + `scale-[1.03]`,
  active `scale-[0.99]`.
- **Secondary action**: no filled secondary exists — it's a tracked uppercase text link
  with an arrow (`READ →`, `HOW REFUNDS WORK ↓`), red or white/60, hover red.
- **Inputs**: transparent, square, underline-style (hairline bottom), 50px tall,
  `padding 12px 0`; labels are 10–12px tracked uppercase.
- **Subpage header**: hairline-bottom bar (`border-b red/20 px-6 py-5`), `← Snatch It`
  back-link left, page label right, both tracked uppercase micro.
- **Footer**: centered stack — Oswald red wordmark (subtle glow) → tagline white/40
  0.4em → link row white/60 0.3em (hover red) → `© 2026 SNATCH IT · JDT LLC · MIAMI, FL`.
- **FAQ**: native `<details class="group py-6">` in a red-hairline `divide-y`, `+` marker.
- **Status eyebrow**: `NOW LIVE · MIAMI` — tracked uppercase micro with interpunct.

## 6. Motion

- `transition-colors` (150–200ms) on links; buttons `transition-all duration-200` with
  scale + glow; `.flicker` 3s opacity loop on the hero wordmark; `@keyframes pulse-red`
  box-shadow pulse for live indicators; `@keyframes glitch` defined (used sparingly).
- `prefers-reduced-motion: reduce` globally forces `animation/transition-duration: 0.01ms`
  and kills `.flicker` + smooth scroll.

## 7. Marketplace translation rules (what carries, what adapts)

Carries verbatim: Oswald/Inter pairing and weights, `#FF1A1A` + black + white opacity
ladders, red hairlines, radius 0, black-on-red primary button + glow, tracked-uppercase
label voice, slash/interpunct separators, red hover affordance, numeral motif, atmosphere
underlay + grain, sticky-CTA pattern, reduced-motion policy.

Adapts for a functional marketplace (density the marketing site never faces):
- Listing cards get a real container — site's own `--card #0a0a0a` + red/15 hairline,
  square corners, hover: border red/40 + title turns red (journal motif) + image scale.
- Functional label tracking capped at 0.25–0.3em (the site's own nav value); 0.5em is
  reserved for section eyebrows. 10px type only for micro-labels, body UI ≥ 13px.
- Glow restricted to: display headings, primary CTA, wordmark, live indicators.
  Never on card borders or prices ("red as a scalpel, never a wash").
- Prices set in Oswald 700 (the auction-board voice) with Inter for breakdown rows.
