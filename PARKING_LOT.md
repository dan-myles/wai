# Parking lot

Ideas we're not working on yet. Each needs a feasibility check first.

Nothing is open right now.

## Done
- **Auto-updating tab titles (v0.6.0):** Claude titles a chat with a hidden `[[title:…]]` on its first reply and again when the topic shifts; the context tells it the current title and whether the player named the tab; hand-named tabs never change; new titles fade in with a gold glow.
- **Opt-in telemetry (v0.5.0):** off by default; a one-time consent banner and a Privacy section in `/settings` (switch plus "See what's sent"); scrubbed Lua errors and stalled streams from the addon plus bridge errors; `wai telemetry on|off|show|url`; and a validating collector in `apps/telemetry`. Documented in docs/TELEMETRY.md.
- **Minimap button (v0.4.0):** wai's portrait on the minimap ring, built from wai's own primitives: left-click chat, right-click settings, shift-right-click fun, drag around the ring (angle saved), a status dot for working/unread, and a Settings toggle.
- **Settings menu (v0.3.0):** `/settings` or the header gear opens a floating panel with grouped, data-driven settings: typing speed (new segmented control), whisper replies, killstreaks, reset window positions, and an About row with the version, bridge contact, Check for updates and Help. Later releases add their rows to `settings.SECTIONS`.
- **Monorepo structure (v0.2.0):** syncfast's layout: Bun workspaces (`apps/cli`, `apps/addon`, `tooling/typescript|oxfmt|oxlint`) with a version catalog, Turborepo for checks, Task as the single entry point, mise pins, an `AGENTS.md` guide, oxfmt + oxlint (ultracite), and CI through a shared setup action.
- **`wai` CLI with self-update (v0.1.0):** one binary per platform built with `bun build --compile`, release installers with SHA-256 checks, `wai install/run/update/status/logs/uninstall`, in-game `/update` with progress and an update-available banner, video tools on demand, and a GitHub Actions release pipeline.
- **Hot-swappable custom UI slots:** Built as UI modules: Claude writes `ui/<name>.lua`, and the bridge hot-loads each change through 40 `wai_modNN` slots. See apps/cli/SKILL.md.
- **Parallel chats (tabs):** Built: a tab strip with up to 8 chats per character, each its own Claude session. Double-click to rename, right-click to close; tabs are auto-named and show unread and busy dots.
- **Smooth, durable streaming:** Built: a live activity line ("Searching the web for …"), a bridge heartbeat, a slower slot schedule for long tasks, a silent re-sync and then a banner when the bridge goes quiet, a screenshot watchdog, a 30-minute task limit, and recovery for replies cut off by a bridge restart.
- **Killstreaks:** Built (`apps/addon/killstreak.lua`): kills are counted from the game's kill and XP messages, with a gold streak badge. At 11 a thermal-green Chopper Gunner overlay appears with a rotating reticle; at 25 a red-alarm Nuke countdown ends in a white flash. Dying resets the streak, and Claude sees it in context.
- **Play videos on screen:** Built as pixel video. A probe showed WoW never re-reads changed textures and can't see files created after launch, so real-resolution video is impossible on this client. Instead the bridge fetches clips with yt-dlp, and ffmpeg turns them into 80x45 (or 45x80) frames at 8 fps, packed into 200 `wai_vidNNN` slots and painted onto a block grid in a wai-styled player. Clips are capped at 2 minutes, with no sound (audio files hit the same limits).
- **TikTok mode:** Built: `[[tiktok:on]]` docks a looping vertical clip beside the chat with a pulsing LIVE tag, burned-in captions of wai's reply, and Claude-written stream chat dripping in. Replies switch to a zoomer tone.
