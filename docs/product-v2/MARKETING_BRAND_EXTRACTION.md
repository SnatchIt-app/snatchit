# Marketing brand extraction — snatchitapp.com as the product's brand source

**Audited:** 2026-09-02, against the live rendered site at `https://snatchitapp.com/` (computed
styles read from the running document, not from memory or source guesses), cross-checked against
`web/docs/brand-system.md` (the 2026-07-29 measured audit) and the repository's own token files.

**Verdict:** the marketing site's design language is coherent, distinctive and already documented.
The web app follows it. **The mobile app does not.** The single largest brand problem in the
product is not that the app is unpolished; it is that the app is running a *different brand*.

---

## 1. Verified live tokens (read from the running site)

The site publishes its own custom properties on `:root`. Values read live:

| Token | Value |
|---|---|
| `--background` | `#000` |
| `--foreground` | `#fff` |
| `--card` | `#0a0a0a` |
| `--primary` | `#ff1a1a` |
| `--primary-foreground` | `#000` (black text on red) |
| `--border` | `#ff1a1a` |
| `--ring` | `#ff1a1a` |
| `--muted` / `--secondary` | `#111` |
| `--muted-foreground` | `#666` |
| `--radius` | `0` |

Body computes to Inter at 16px, white on pure black. Every measured element returned
`border-radius: 0px`. The 2026-07-29 audit remains accurate: nothing has drifted.

## 2. Verified live typography

| Role | Family | Size | Weight | Tracking | Case |
|---|---|---|---|---|---|
| Hero H1 | Oswald (fallback Impact, Arial Black) | 166.4px | 700 | -3.328px (-0.02em) | uppercase |
| Section H2 | Oswald | 72px | 700 | -1.44px (-0.02em) | uppercase |
| Primary CTA | Inter | 13px | 700 | +2.34px (+0.18em) | uppercase |
| Body | Inter | 16px | 400 | normal | sentence |

The system is two-family and strictly divided: **Oswald carries display type, always uppercase,
always negatively tracked, very large. Inter carries everything else, and its uppercase labels are
widely positively tracked at small sizes.** That opposition (tight huge display against wide tiny
labels) is the brand's typographic signature. Line height on display is sub-1.0 (H1 computes
136.4px leading on a 166.4px face, roughly 0.82), which is what makes the headlines feel stacked
and poster-like rather than webby.

Fonts are self-hosted through `next/font/google`, not a CDN, with real fallbacks declared.

## 3. Verified imagery treatment on the marketing site

- Atmosphere photography (`/atmosphere/*.jpg`: crowd, yacht-night, show-crowd, arena-crowd,
  miami-street) is used as **low-key underlay**, at opacity 0.08 to 0.22 over black, so images
  emerge from darkness rather than sitting on top of it.
- A global SVG fractal-noise grain overlay runs at opacity 0.03 above everything.
- The hero adds a large red glow (blur 180px) and thin rotated red light streaks.
- Every image measured returned `border-radius: 0`. Square is absolute on this brand.
- Ratios in use are deliberately mixed by context: 1.38 (hero underlay), 1.79 (landscape pair),
  1.00 (square), 0.75 (portrait), 0.46 (phone screenshots). The site does not force one ratio.

**Two defects observed on the live site, relevant to the product redesign:**

1. **No image transformation anywhere.** Every image URL is served raw with zero query
   parameters. There is no width negotiation, no quality parameter, no modern format, no
   `srcset`. `atmosphere/crowd.jpg` is natively 1280x853 and is painted into a 1376x999 box,
   so it is upscaled past its own resolution on a desktop viewport.
2. **A real event cover is being destroyed by its container.** The featured event image pulled
   from app storage (`.../covers/1783029690066.jpg`) is natively **1173x609, a 1.93:1 landscape**,
   and is rendered into a **358x448, 0.80:1 portrait** box under `object-fit: cover`. The
   container is 2.4x off the source ratio, so roughly 58% of the image is cropped away, centred,
   with no focal-point control. This is the clearest evidence that Snatch It has no event media
   system: the same asset cannot serve both a landscape hero and a portrait card, and today
   nothing decides which part of it survives.

## 4. Verified brand voice and positioning

Copy read from the live page, quoted because it directly constrains the product's information
architecture:

- "Buy tickets straight from the event, or bid and Buy Now on the ones other fans can't use.
  One place, from the drop to the door."
- "FOR VENUES & ORGANIZERS / FILL THE ROOM. OWN THE CROWD. Sell your tickets directly through
  Snatch It, and keep the resale when the night sells out."
- Journal headline: "SNATCH IT NOW SELLS TICKETS DIRECTLY FOR MIAMI VENUES AND EVENTS."
- Page title: "Snatch It: Miami Event Tickets, **Direct and Marketplace**."

Three consequences:

1. **The marketing site already sells venue-native ticketing.** The promise is live; the product
   rail behind it is dark. Track A is not a speculative feature, it is closing a gap between what
   the company already says publicly and what the app can do.
2. **The customer vocabulary is fixed and it is not our internal vocabulary.** The brand says
   **"direct"** and **"marketplace"**. It never says primary, secondary, resale rail, inventory
   batch, or atom. The product UI must inherit "direct" and "marketplace".
3. **The site is already event-first, not listing-first.** "UP NEXT IN MIAMI / WHERE THE CITY IS
   GOING" presents an event (III POINTS SATURDAY GA, venue, date), not a resale listing. The app,
   which is listing-first, is behind its own marketing on this point.

Voice rules observable in the copy: sentences with full stops, rendered uppercase by CSS; short
declaratives; second person; no exclamation marks; no jargon. "The night, in writing." is the
register.

## 5. The brand fork: mobile is a different product

This is the finding that matters most. The repository contains **two competing token systems**.

| Concern | Marketing site and web app | Mobile app (`src/theme/index.ts`) |
|---|---|---|
| Canvas | `#000` true black | `#0B0F14` blue-black |
| Card surface | `#0a0a0a` neutral | `#11161C` blue-gray |
| Brand red | `#FF1A1A` | `#E10600` |
| CTA text on red | `#000` black | white |
| Borders | red hairlines, `rgba(255,26,26,0.15)` | `#1C232B` blue-gray |
| Radius | `0` everywhere | 6 / 10 / 16 / 24 / 9999 |
| Muted text | white at 70% | `#8a94a6` blue-gray |
| Display font | Oswald 700 uppercase | none |
| Body font | Inter | none |
| Stray tokens | none | `badge: #ffd700` gold |

Two hard facts behind that table:

- **The mobile app loads no custom font at all.** `expo-font` is a declared dependency, but there
  is no `useFonts` call and no font asset loaded anywhere in `app/` or `src/`. Every screen
  renders in the OS system face. The brand's entire typographic identity is absent from the
  product customers actually use.
- **The token package inverted the source of truth.** `packages/design-tokens/tokens.css` is
  auto-generated and its header names `mobile src/theme/index.ts` as the source. The web app then
  has to override those tokens back to brand values in `web/src/app/globals.css`. So the
  non-brand system is upstream of the brand-correct one.

The mobile palette is a competent dark-app theme. It is simply not Snatch It. A user moving from
the website to the app crosses a visible seam: the black turns blue, the red shifts orange-ward,
the corners round off, and the type loses its voice.

## 6. What the product must inherit

Non-negotiable, because it defines the brand:

1. **True black `#000`**, neutral `#0a0a0a` surfaces, no blue in the neutrals.
2. **`#FF1A1A` red, with black type on red** for primary actions.
3. **Radius 0.** Square buttons, inputs, cards, badges, images.
4. **Red-tinted hairlines** at 15% to 30% instead of gray borders.
5. **Oswald 700 uppercase, negatively tracked, for display; Inter for everything else**, with
   Inter's small uppercase labels widely tracked.
6. **Images emerge from black**, they do not sit on it. Dark, low-key, cinematic.
7. **"Direct" and "marketplace"** as the customer-facing words.

## 7. Where the product must diverge from the marketing site

The site is a poster. The app is a tool that takes money. Translating literally would hurt.

| Marketing device | Product treatment |
|---|---|
| 166px hero display type | Cap display at roughly 32 to 44px on mobile. Oswald stays for event titles and screen titles only. |
| Images at 8 to 22% opacity | Event artwork is the product. Show it at full strength; reserve heavy dimming for backdrops behind text. |
| Global grain, red glow, light streaks | Drop from transactional surfaces. Optional on empty states and confirmations. Never behind a price or a QR code. |
| Wide `+0.5em` tracking on labels | Keep only for micro labels at 10 to 12px. Never on body, prices, or long strings. |
| Uppercase everything display | Keep uppercase for labels and titles. Never uppercase user-generated event names, which arrive in mixed case and become unreadable. |
| Hairline-only separation, no cards | The app needs tap targets. Keep square edges and red hairlines, but allow real surfaces at `#0a0a0a`. |

Accessibility guardrails: `#FF1A1A` on `#000` is a strong contrast for large type but must never
carry small body text; use white for reading and red for accent and action. White at 45% or below
is decoration, never information. Every red-only state needs a non-color cue.

## 8. Evidence index

- Live computed styles and page text: `https://snatchitapp.com/`, read 2026-09-02.
- Prior measured audit: `web/docs/brand-system.md`.
- Web token implementation: `web/src/app/globals.css`.
- Mobile token implementation: `src/theme/index.ts`.
- Generated shared tokens and their stated source: `packages/design-tokens/tokens.css`.
