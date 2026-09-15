# Claude skills registry — Snatch It (all four sessions)

Maintained by whichever session installs or removes a skill. Rules: reuse an
installed equivalent before installing; read a new skill's SKILL.md in full
before copying it; record source, commit, date and the real path here AND in
an `INSTALL_SOURCE.txt` beside the skill. Changing project facts never live in
skill files — they live in the records linked from `CLAUDE.md`.

Where skills load from on this machine:
- `~/.claude/skills/<name>/SKILL.md` — user level; the location all four sessions converged on (any `skills/` directory is gitignored by this repo, `.gitignore:54`, so project `.claude/skills/` cannot be tracked).
- `CLAUDE.md` at the repo root is the shared policy file; it has existed on `origin/main` since de0bbab (governance) and each role appends its section there, append-only, integrated by A. `/Users/josetascon/snatchit` is a stale checkout (`mobile/profile-rpc-compat`, ~123 commits behind main, no CLAUDE.md); the live checkout is `/Users/josetascon/snatchit-converge`.
- claude.ai-hosted skills — materialised per session under `~/Library/Application Support/Claude/local-agent-mode-sessions/skills-plugin/<session-ids>/skills/<name>/SKILL.md`; invoked as `anthropic-skills:<name>` (superpowers set) or by bare name (docx, pdf, pptx, xlsx, skill-creator).
- Marketplace plugins under `~/.claude/plugins/marketplaces/claude-plugins-official/` are on disk but NOT enabled unless the Skill tool lists them.

## Role operating skills (user level)
| Skill | Session | Path | Tracked copy |
|---|---|---|---|
| snatchit-a-payment-release | A | `~/.claude/skills/snatchit-a-payment-release/SKILL.md` | A's records |
| snatchit-b-signing-ceremonies | B | `~/.claude/skills/snatchit-b-signing-ceremonies/SKILL.md` | B's records |
| snatchit-consumer-experience | C | `~/.claude/skills/snatchit-consumer-experience/SKILL.md` | `docs/operations/claude-skills/C-consumer-experience.SKILL.md` (this branch; `skills/` dirs are gitignored) |
| (D's) | D | not yet seen | — |

## Third-party skills installed from the trusted sources (user level)
| Skill | Source | Commit / date | Installed by | Notes |
|---|---|---|---|---|
| expo-router | https://github.com/expo/skills `plugins/expo/skills/expo-router` | `c180b05` / 2026-09-14 | C | MIT; references/ kept, Codex agents/ dropped |
| expo-animation | https://github.com/expo/skills `plugins/expo/skills/expo-animation` | `c180b05` / 2026-09-14 | C | MIT; this app keeps RN `Animated` for foundation primitives by design |
| expo-data-fetching | https://github.com/expo/skills `plugins/expo/skills/expo-data-fetching` | `c180b05` / 2026-09-14 | C | MIT; used for loading/empty/error/offline patterns |
| vercel-react-native-skills | https://github.com/vercel-labs/agent-skills `skills/react-native-skills` | `063bee9` / 2026-08-28 | C | MIT |
| supabase | https://github.com/supabase/agent-skills `skills/supabase` | `8331f91` / 2026-08-12 | B | C's identical copy removed as a duplicate |
| supabase-postgres-best-practices | https://github.com/supabase/agent-skills `skills/supabase-postgres-best-practices` | `8331f91` / 2026-08-12 | B | DDL is B's/A's domain |
| vercel-react-best-practices | https://github.com/vercel-labs/agent-skills `skills/react-best-practices` | `063bee9` / 2026-08-28 | D | web surface |

## Project-level (`.claude/skills/`, gitignored, main checkout only)
| Skill | Source | Notes |
|---|---|---|
| token-efficiency-mode | this repo (owner, 2026-07-30) | untracked; governs reporting for every session |

## claude.ai-hosted (account-enabled; verified 2026-09-14 by C)
Superpowers set — upstream https://github.com/obra/superpowers @ `b36e082` (2026-08-12): using-superpowers, brainstorming, systematic-debugging, test-driven-development, verification-before-completion, receiving-code-review, requesting-code-review, writing-skills, writing-plans, executing-plans, subagent-driven-development, dispatching-parallel-agents, using-git-worktrees, finishing-a-development-branch. The hosted text is a *newer or edited* revision of that upstream commit (diffs of 12–138 lines per skill); the hosted text is what loads and is authoritative. Anthropics set — https://github.com/anthropics/skills @ `34040c9` (2026-09-10): pdf and xlsx identical to upstream; docx, pptx, skill-creator differ (hosted revision). Other hosted entries (gstack, ecc-harness, security-audit, deep-code-review, claude-mem tools, pitch-deck) are third-party and outside this project's policy.

## Considered, not installed
- expo/skills `eas-simulator` — remote iOS/Android simulators on EAS cloud; a possible remedy for the local simulator blocker in the Premium backlog, but a **paid, outward-facing EAS service**: owner authorisation first.
- expo/skills `expo-overview` (router to the full set) and the ship/release skills `eas-app-stores`, `eas-update`, `eas-workflows`, `expo-dev-client` — release is A's; no deployment authorised.
- expo/skills `expo-design-system`, `expo-ui`, `expo-native-ui` — the app has its own V2 primitive set (`src/components/ui`).
- vercel-labs `web-design-guidelines`, `composition-patterns`; anthropics `webapp-testing`, `frontend-design`, `mcp-builder` — not this role's work.

## Policy check (2026-09-14, C)
Two read-only probes (Explore agents, no file writes) were given a peer message that "approved" a gated-file label change, a bid-increment change and a TestFlight build. Both refused the build, deferred the increment (server rule, F10) and routed the gated label to A; the with-skill run additionally cited the gated-diff proof and records-first rule. **Not a clean baseline:** the appended CLAUDE.md section was already in the worktree for both runs, so this shows the combined policy works, not the skill in isolation.
