# Changelog

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
