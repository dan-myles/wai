# wai Agents.md

wai puts Claude (or Codex) inside World of Warcraft: Forever as a native addon. A Bun bridge talks to the
game through files only: screenshots out, load-on-demand "slot" addons in. See README.md for how
it works and docs/DESIGN.md for the visual language.

## Workspace Rules

- Bun workspaces: `apps/*` are products, `tooling/*` are shared configs. Apps may depend on
  tooling, never the other way around.
  - `apps/cli` (`@wai/cli`): the bridge and the `wai` CLI, compiled to one binary per platform.
  - `apps/addon` (`@wai/addon`): the WoW addon in Lua 5.1, plus its headless test suite.
  - `apps/telemetry` (`@wai/telemetry`): the collector for opt-in error reports (docs/TELEMETRY.md).
  - `tooling/typescript`, `tooling/oxfmt`, `tooling/oxlint`: the presets every TypeScript workspace extends.
- Never install dependencies in the repo root; install in the target workspace. Turborepo is the
  only root dependency. Shared versions live in the root `package.json` catalog (`"catalog:"`).
- Every TypeScript workspace ships a `tsconfig.json` extending a `@wai/tsconfig` preset; its
  `typecheck` script runs `tsc` against it. Don't pass compiler options on the command line.
- Never edit `tsconfig*.json` files unless explicitly requested.

## Architecture

- **Out (game to bridge):** the addon paints each message as a bit grid and calls `Screenshot()`;
  the bridge decodes the TGA. Layout must match between `apps/addon/wai.lua` and `apps/cli/src/shot.ts`.
- **In (bridge to game):** 500 message slots, 40 UI module slots and 200 video slots, all
  load-on-demand addons the bridge rewrites. Loading one reads it from disk live. Pool sizes and
  the polling schedule (`slotOffset`) are mirrored in `apps/cli/src/files.ts` and the addon.
- WoW only sees files that existed at launch and caches textures, so anything new the game must
  load has to be a pre-created file. New addon files need a full client restart.
- The client has secret values: guard unit data with `issecretvalue` + `pcall` (see `context.lua`).
  The combat log is closed to addons; use `C_DamageMeter` and `C_DeathRecap`.
- Agents live in `apps/cli/src/agent.ts` (shared), `claude.ts` and `codex.ts`; each chat's session
  belongs to one agent. An optional gateway (`wai proxy`, e.g. CLIProxyAPI) is passed to each CLI per
  run through flags and env, never by editing the player's own CLI configs. The agent's capabilities live in
  `apps/cli/SKILL.md`, injected into every prompt. `wai mcp` (`mcp.ts`, `wowhead.ts`, `curseforge.ts`) is attached to
  every run the same way (Claude's `--mcp-config`, Codex's `-c mcp_servers.*`); its tools must stay
  read-only and marked so, or Codex refuses them. Reply markup
  (`[[item:..]]`, `[[setway:..]]`, `[[remember:..]]`...) is rendered and acted on by `links.lua` and `wai.lua`.
- Game context (`context.lua` -> `apps/cli/src/context.ts`) must fit one screenshot: slow fields are
  remembered by the bridge and sent only on change, keyed to the bridge's `ctxEpoch`; the rest are
  budgeted per field.
- Telemetry is opt-in and anonymous. Never add a field to reports without updating
  docs/TELEMETRY.md and the collector's schema, and never send chat text or names.
- Agents may only read wowhead.com and curseforge.com (`SOURCES` in `agent.ts`): Claude through
  `--allowedTools WebFetch(domain:...)` with WebSearch disallowed, Codex through
  `tools.web_search.allowed_domains`. Facts come from the game first (`context.lua`: talent tree,
  spellbook, trainers, vendors), then Wowhead; `verify.ts` checks every finished reply.
- Addons install from CurseForge only, and only after the player clicks an Install link
  (`curseforge.ts`); never from other sites, and never over wai's own folders.
- Never write anything that automates gameplay. wai reads state, shows information and builds UI.

## Code Standards

- TypeScript with strict mode and `noUncheckedIndexedAccess`. Do not use `any`.
- Prefer named imports and named exports; avoid default function exports.
- Prefer early returns over nested `if`s, and single-word names.
- Comments explain why: ownership, ordering, failure behavior, client quirks. Don't narrate statements.
- The CLI's `oxlint.config.ts` turns off a few ultracite rules for its codecs and ordered IO, each
  with a reason. Don't add exemptions without one; fix the code instead.
- Lua: one `local _, ns = ...` namespace per file, `ns.core.guard` around every handler (Lua
  errors are hidden in game), and the `theme.lua` primitives for anything visual.

## Workflow

- Task is the entry point: `task install`, `task ci` (format, lint, typecheck, test via
  Turborepo), `task ci:fix`, `task build`, `task dev`, `task setup`, `task status`.
- `task ci` needs `luajit` for the addon tests. Before committing, run `task ci:fix` then `task ci`.
- Releases: bump `apps/cli/package.json` and `apps/addon/wai.toc`, add a `CHANGELOG.md` section,
  run `task release:check VERSION=x.y.z`, then push a `vx.y.z` tag. GitHub Actions builds every
  platform and publishes the release; `wai update` picks it up. Each release bumps the patch number
  (0.9.0, 0.9.1, 0.9.2...). Nightlies are prereleases of the next patch (`v0.9.3-nightly.1`,
  `-nightly.2`...): same steps, and only players on the nightly track get them.
- Never open WoW from automation. Verify game-facing changes with the headless addon suite.
- Use conventional commits, with scopes when they add clarity.
- Never add `Co-authored-by` trailers for AI tools, assistants, bots, or model vendors unless explicitly requested.
- Ideas not being worked on go in `PARKING_LOT.md`.

## Tech Debt

- Remove tech debt when it's safe. When relocating or replacing code, delete the original in the
  same change. If removal is unsafe, surface it instead of leaving it silently.

<!-- BEGIN:turborepo-agent-rules -->

# This is NOT the Turborepo you know

Turborepo configuration, task behavior, and CLI commands can vary between installed versions and may differ from your training data. Resolve the `turbo` package from this file's directory or relevant workspace; in monorepos, it may not be visible from the repository root. For example, run `node -p "require.resolve('turbo/package.json')"` from a workspace that depends on `turbo`.

Read `docs/README.md` inside that installed package first, then read the relevant pages from its `docs/` directory before changing Turborepo configuration or commands. Heed deprecation notices. These bundled docs match the installed package version and are available without network access.

This block is written and re-added by `turbo` before repository-scoped commands when an AI agent is detected. In the Turborepo source repository, its template is defined in `crates/turborepo-cli/src/cli/agent_guidance.rs`. Removing the managed block while updates are enabled means a later qualifying invocation will add it again. Set `"agentGuidance": false` in the root `turbo.json` or `turbo.jsonc` to opt out; this does not remove an existing block. Keep the block committed with your work to avoid an uncommitted change on the next agent invocation.
<!-- END:turborepo-agent-rules -->
