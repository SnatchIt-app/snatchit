# Snatch It — Web (Phase 0 visual proof)

Dedicated Next.js 16 app (App Router, TS strict, Tailwind 4) proving the web
architecture against the existing Supabase backend. Built per the Web Platform
Architecture Report; the Expo mobile app at the repo root is untouched.

## Pages

- `/` — homepage (hero + search, live listings, trust, sell CTA, app CTA)
- `/browse` — server-filtered marketplace grid (URL-driven filters, mobile sheet)
- `/listing/[id]` — listing detail (all-in price breakdown via `@snatchit/core`,
  sticky purchase card, Event JSON-LD). Checkout is intentionally NOT enabled.

## Commands

```bash
npm run dev            # dev server
npm run build          # production build
npm run smoke          # build first; boots next start and checks 6 routes
npm test               # web unit tests (listing display helpers)
npm run test:packages  # 108 parity tests for @snatchit/* vs mobile + server
npm run typecheck && npm run lint
npm run sync:packages  # re-vendor ../packages into vendor/*.tgz after changes
```

## Shared packages

`@snatchit/{types,core,design-tokens}` are consumed as vendored tarballs in
`vendor/` (committed) because `vercel build` roots the build at `web/` and
cannot see `../packages`. `../packages` remains the source of truth — run
`npm run sync:packages` after editing them. The post-App-Review pnpm monorepo
replaces this mechanism.

## Environment

Copy `.env.example` → `.env.local`. Public-class values only (Supabase URL +
anon/publishable key — the same trust class shipped in the mobile binary).
The service-role key must never appear anywhere in this app.

## Deploy (private preview)

Vercel project `snatchit-web` (team gnvprod-5449s-projects), Vercel
Authentication protects preview URLs. Production target is intentionally
unused — do not attach domains or promote until approved.

```bash
npm run sync:packages
npx vercel@latest build
npx vercel@latest deploy --prebuilt --archive=tgz   # preview target
```

(Prebuilt deploys sidestep remote installs; use `vercel@latest` — the globally
installed v50 mistargets production for prebuilt deploys.)
