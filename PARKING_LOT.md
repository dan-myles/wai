# Parking lot

Ideas we're not working on yet. Each needs a feasibility check first.

## Monorepo structure (syncfast template)
Restructure this repo after `~/Developer/personal/syncfast`, which becomes the monorepo template for wai's addon, bridge and CLI.
- Check syncfast's layout, tooling and conventions first, then map `addon/`, `bridge/`, the installers and the docs onto it.

## Opt-in telemetry
Anonymous, opt-in usage and error reporting (off by default) to learn what breaks in the field: bridge errors, decode failures, stalled streams, Lua errors, client version and OS.
- Turned on and off with a toggle in the new `/settings` menu (see below), plus a consent prompt the first time. A "see what's sent" view lives there too.
- Never chat content or character names.

## Settings menu (`/settings`)
A new `/settings` command in the wai chat opens a settings panel in the same modern design as the Fun menu (floating, sections, `T.toggle` switches), built for growth.
- First settings: telemetry (opt-in), minimap button on/off, typing speed, whisper replies to chat when the window is closed, killstreaks (mirrors `/fun`).
- Sections with gold uppercase labels and faded lines, a short hint under each setting, saved per character or per account as fits.

## Minimap button
A round wai portrait button on the minimap ring (gold ring, arcane icon) that toggles the wai window: left-click opens/closes, right-click opens `/fun` or `/settings`, drag to move around the ring.
- Built with wai's own primitives (no LibDBIcon or other addons). Can be hidden from `/settings`.

## Auto-updating tab titles
Tabs are named once, from the first message ("best leveling route fo"). Instead, keep the title current as the conversation moves on.
- Claude proposes a short title (2–4 words, e.g. "Hunter leveling route") on the first reply and refreshes it when the topic clearly shifts, through a `[[title:...]]` markup token (or a cheap separate summary call on the bridge).
- Never overwrite a title the player renamed by hand (`auto` flag already tracks that). Animate the change subtly in the tab strip.

## Done
- **`wai` CLI with self-update (v0.1.0):** one binary per platform built with `bun build --compile`, release installers with SHA-256 checks, `wai install/run/update/status/logs/uninstall`, in-game `/update` with progress and an update-available banner, video tools on demand, and a GitHub Actions release pipeline.
- **Hot-swappable custom UI slots:** Built as UI modules: Claude writes `ui/<name>.lua`, and the bridge hot-loads each change through 40 `wai_modNN` slots. See bridge/SKILL.md.
- **Parallel chats (tabs):** Built: a tab strip with up to 8 chats per character, each its own Claude session. Double-click to rename, right-click to close; tabs are auto-named and show unread and busy dots.
- **Smooth, durable streaming:** Built: a live activity line ("Searching the web for …"), a bridge heartbeat, a slower slot schedule for long tasks, a silent re-sync and then a banner when the bridge goes quiet, a screenshot watchdog, a 30-minute task limit, and recovery for replies cut off by a bridge restart.
- **Killstreaks:** Built (`addon/killstreak.lua`): kills are counted from the game's kill and XP messages, with a gold streak badge. At 11 a thermal-green Chopper Gunner overlay appears with a rotating reticle; at 25 a red-alarm Nuke countdown ends in a white flash. Dying resets the streak, and Claude sees it in context.
- **Play videos on screen:** Built as pixel video. A probe showed WoW never re-reads changed textures and can't see files created after launch, so real-resolution video is impossible on this client. Instead the bridge fetches clips with yt-dlp, and ffmpeg turns them into 80x45 (or 45x80) frames at 8 fps, packed into 200 `wai_vidNNN` slots and painted onto a block grid in a wai-styled player. Clips are capped at 2 minutes, with no sound (audio files hit the same limits).
- **TikTok mode:** Built: `[[tiktok:on]]` docks a looping vertical clip beside the chat with a pulsing LIVE tag, burned-in captions of wai's reply, and Claude-written stream chat dripping in. Replies switch to a zoomer tone.
