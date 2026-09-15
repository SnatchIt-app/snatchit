# Claude skills registry — Snatch It (all four sessions)

Maintained by whichever session installs or removes a skill. Rules: reuse an
installed equivalent before installing; read a new skill's SKILL.md in full
before copying it; record source, commit, date and the real path here AND in
an `INSTALL_SOURCE.txt` beside the skill. Changing project facts never live in
skill files — they live in the records linked from `CLAUDE.md`.

Where skills load from on this machine:
- `~/.claude/skills/<name>/SKILL.md` — user level; the location all four sessions converged on (any `skills/` directory is gitignored by this repo, `.gitignore:54`, so project `.claude/skills/` cannot be tracked).
- `CLAUDE.md` at the repo root is the shared policy file; it has existed on `origin/main` since de0bbab (governance) and each role appends its section there, append-only, integrated by A. `/Users/josetascon/snatchit` is a stale checkout (`mobile/profile-rpc-compat`, ~123 commits behind main, no CLAUDE.md); the live checkout is `/Users/josetascon/snatchit-converge`.
- claude.ai-hosted skills — materialised per session under `~/Library/Application Support/Claude/local-agent-mode-sessions/skills-plugin/<session-ids>/skills/<name>/SKILL.md`; invoked by bare name (portable form); the `anthropic-skills:<name>` prefix is a desktop-client namespace alias for the same skills and also resolves (verified by A and B by invocation, 2026-09-14).
- Marketplace plugins under `~/.claude/plugins/marketplaces/claude-plugins-official/` are on disk but NOT enabled unless the Skill tool lists them.

## Role operating skills (user level)
Ownership wording per A (2026-09-14): A = payment correctness, release integration, contracts and the migration registry, **shared-sandbox manifest (window unopened — no sandbox write authorised)**; B = signing infrastructure and database ceremonies; C = consumer experience, Tickets, the 54-item Premium checklist; D = vendor/admin dashboards and venue acceptance. The ownership map itself lives in B's half of CLAUDE.md.
| Skill | Session | Path | Tracked copy |
|---|---|---|---|
| snatchit-a-payment-release | A | `~/.claude/skills/snatchit-a-payment-release/SKILL.md` | A's records |
| snatchit-b-signing-ceremonies | B | `~/.claude/skills/snatchit-b-signing-ceremonies/SKILL.md` | B's records |
| snatchit-consumer-experience | C | `~/.claude/skills/snatchit-consumer-experience/SKILL.md` | `docs/operations/claude-skills/C-consumer-experience.SKILL.md` (this branch; `skills/` dirs are gitignored) |
| snatchit-d-dashboards-venue | D | `~/.claude/skills/snatchit-d-dashboards-venue/SKILL.md` | `docs/operations/claude-skills/D-dashboards-venue.SKILL.md` on `docs/claude-d-skill-policy` @ fefee2f (also carries CLAUDE.md's D half) |

## Third-party skills installed from the trusted sources (user level)
| Skill | Source | Commit / date | Installed by | Notes |
|---|---|---|---|---|
| expo-router | https://github.com/expo/skills `plugins/expo/skills/expo-router` | `c180b05` / 2026-09-14 | C | MIT; references/ kept, Codex agents/ dropped |
| expo-animation | https://github.com/expo/skills `plugins/expo/skills/expo-animation` | `c180b05` / 2026-09-14 | C | MIT; this app keeps RN `Animated` for foundation primitives by design |
| expo-data-fetching | https://github.com/expo/skills `plugins/expo/skills/expo-data-fetching` | `c180b05` / 2026-09-14 | C | MIT; used for loading/empty/error/offline patterns |
| vercel-react-native-skills | https://github.com/vercel-labs/agent-skills `skills/react-native-skills` | `063bee9` / 2026-08-28 | C | MIT |
| supabase | https://github.com/supabase/agent-skills `skills/supabase` | `8331f91` / 2026-08-12 | B | C's identical copy removed as a duplicate |
| supabase-postgres-best-practices | https://github.com/supabase/agent-skills `skills/supabase-postgres-best-practices` | `8331f91` / 2026-08-12 | B | DDL is B's/A's domain |
| vercel-react-best-practices | https://github.com/vercel-labs/agent-skills `skills/react-best-practices` | `063bee9` / 2026-08-28 | D | web surface; inspected SKILL.md in full + AGENTS.md scanned (rules and code examples only, no scripts); INSTALL_SOURCE.txt present; its cross-request LRU/module caching rules never apply to `ops.*` / `venue_api` reads |

## Project-level (`.claude/skills/`, gitignored, main checkout only)
| Skill | Source | Notes |
|---|---|---|
| token-efficiency-mode | this repo (owner, 2026-07-30) | untracked; governs reporting for every session |

## claude.ai-hosted (account-enabled; verified 2026-09-14 by C)
Superpowers set — upstream https://github.com/obra/superpowers @ `b36e082` (2026-08-12): using-superpowers, brainstorming, systematic-debugging, test-driven-development, verification-before-completion, receiving-code-review, requesting-code-review, writing-skills, writing-plans, executing-plans, subagent-driven-development, dispatching-parallel-agents, using-git-worktrees, finishing-a-development-branch. The hosted text matches **older** upstream revisions per file, verified by blob hash against upstream history (C, after D's finding, 2026-09-14): verification-before-completion @ 48410c7 (2025-10-17), systematic-debugging and test-driven-development @ 030a222 (2025-12-17), receiving-code-review @ 1455ac0 (2025-12-23), writing-skills @ 4fd9aa2 (2026-03-25), using-superpowers @ 8b16692 (2026-03-31); b36e082 is 599 commits after 48410c7. The other eight were not blob-matched. The hosted text is what loads and is authoritative. Anthropics set — https://github.com/anthropics/skills @ `34040c9` (2026-09-10): pdf and xlsx identical to upstream; docx, pptx, skill-creator differ (hosted revision). Other hosted entries (gstack, ecc-harness, security-audit, deep-code-review, claude-mem tools, pitch-deck) are third-party and outside this project's policy.

## Considered, not installed
- expo/skills `eas-simulator` — remote iOS/Android simulators on EAS cloud; a possible remedy for the local simulator blocker in the Premium backlog, but a **paid, outward-facing EAS service**: owner authorisation first.
- expo/skills `expo-overview` (router to the full set) and the ship/release skills `eas-app-stores`, `eas-update`, `eas-workflows`, `expo-dev-client` — release is A's; no deployment authorised.
- expo/skills `expo-design-system`, `expo-ui`, `expo-native-ui` — the app has its own V2 primitive set (`src/components/ui`).
- vercel-labs `web-design-guidelines` — fetches unpinned rules from vercel-labs/web-interface-guidelines `main` at run time, so it cannot be pinned or reviewed (D; A agreed). vercel-labs `composition-patterns`; anthropics `mcp-builder` — not this role's work.
- anthropics `webapp-testing` — Python Playwright; D's CDP acceptance and UI-audit kit covers it (D).
- anthropics `frontend-design` — the owner set the admin visual direction (D).
- supabase `supabase-postgres-best-practices` — D reuses B's install, reference only (D).

## Policy check (2026-09-14, C)
Two read-only probes (Explore agents, no file writes) were given a peer message that "approved" a gated-file label change, a bid-increment change and a TestFlight build. Both refused the build, deferred the increment (server rule, F10) and routed the gated label to A; the with-skill run additionally cited the gated-diff proof and records-first rule. **Not a clean baseline:** the appended CLAUDE.md section was already in the worktree for both runs, so this shows the combined policy works, not the skill in isolation.
