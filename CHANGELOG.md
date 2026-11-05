# Changelog

## 0.2.0 (2026-11-05)

The repo now follows the syncfast monorepo template. No change in game beyond the version number.

- **Layout:** Bun workspaces: `apps/cli` (bridge and CLI), `apps/addon` (the WoW addon), and
  `tooling/typescript`, `tooling/oxfmt` and `tooling/oxlint` for shared presets. Versions are pinned
  in the root catalog.
- **Commands:** Task is the single entry point (`task ci`, `task build`, `task dev`, `task setup`,
  `task release:check`), with Turborepo running format, lint, typecheck and tests in every workspace.
- **Code quality:** oxfmt and oxlint (ultracite) across the CLI, which caught a variable shadowing the
  update function. TypeScript now runs with `noUncheckedIndexedAccess`.
- **Docs:** `AGENTS.md` (also `CLAUDE.md`) guides agents; the design guide moved to `docs/DESIGN.md`.
- **Fix:** `wai install` on macOS retries launchd registration while a previous registration is
  still unloading, instead of failing with "Input/output error".
- CI and releases run through a shared setup action and `actions/checkout@v5`.

## 0.1.0 (2026-11-05)

The `wai` CLI, with self-update. wai now ships as one standalone binary per platform (macOS arm64/x64,
Windows x64, Linux x64) carrying the bridge, the CLI and the addon.

- **Install:** `curl -fsSL …/install.sh | sh` (macOS/Linux) or `install.ps1` (Windows) downloads the
  binary for your machine, checks its SHA-256, installs it to `~/.local/bin` and runs `wai install`.
- **Commands:** `wai install`, `wai run`, `wai update` (`upgrade`), `wai status` (`doctor`), `wai logs [-f]`,
  `wai uninstall [--purge]`, `wai version`.
- **Self-update:** `wai update` replaces a managed install with the latest release after a checksum
  check, installs the new addon and restarts the bridge. It says when WoW needs a restart.
- **In game:** `/update` runs the update from the wai window and reports progress in the chat. The
  bridge checks for new releases daily and shows a banner with an Update button.
- **Video tools on demand:** yt-dlp and ffmpeg download into `~/.wai/bin` the first time they're needed.
- Includes everything built so far: reload-free chat with streaming and live activity, tabs,
  per-character memory, links and waypoints, combat context, alt-click asking, live UI modules,
  killstreaks, pixel video, TikTok mode and the Fun menu.
