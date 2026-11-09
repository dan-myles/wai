# Parking lot

Ideas we're not working on yet. Each needs a feasibility check first.

- **TheWoWDB as a second catalog:** wisp-ai uses `thewowdb.com/api/v1/forever/{kind}/`, but on
  2026-11-09 every route there answered 404 and the site's own database is retail-based (it has the
  Stockade Hogger, 1033, not Elwynn's, 448). Revisit if a Forever API appears: a `thewowdb` tool
  in `wai mcp` and a second opinion in `verify.ts` before flagging something Wowhead lacks.

## Done
- **More Forever sources (v0.9.4-nightly.4):** a `game` tool answered by the client over the link (bundled WhatsTraining Forever training tables; QuestieDB spawns, quests, trainers and services when Questie is installed) and Everloot's Forever-only tools.
- **Live link (v0.9.4-nightly.3):** screenshots and message slots replaced by bit lanes over helper addons' enabled states in AddOns.txt (`link.lua`/`link.ts`), with acks both ways, deflate and change-only messages (`sync.ts`).
- **Forever-only facts (v0.9.4-nightly.2):** game data (talent tree, spellbook, trainer and vendor caches) on demand, sources locked to Wowhead and CurseForge, and a Wowhead check of every reply.
- **Addon installs (v0.9.4-nightly.1):** the agent finds a CurseForge project, checks it has a Forever build with the `curseforge` tool, and offers an Install link; the bridge downloads and unpacks it into AddOns on click.
- **Wowhead tools (v0.9.3-nightly.11):** `wai mcp` gives both agents `search` and `lookup` against Wowhead's Forever JSON endpoints.
- **Settings tabs (v0.9.3-nightly.9):** General / Fun / About; the Fun menu and `/fun` folded into the Fun tab.
- **Wowhead Forever as primary source (v0.9.3-nightly.4):** the skill sends agents to `wowhead.com/forever/<type>=ID` pages before answering game specifics.
- **Context memory (v0.9.3-nightly.2):** the bridge remembers character, notes, talents and the quest log (diffed by quest ID) plus completed quest history; per-field budgets so chat can't crowd them out.
- **Keybind and update tracks (v0.9.3-nightly.1):** set the open key in `/settings`; Stable or Nightly updates there or with `wai track`, nightlies published as prereleases.
- **Tab menu (v0.9.2):** right-click a tab for Rename / Delete (confirmed) instead of closing it.
- **Macros (v0.9.1):** the agent creates, edits and deletes macros with a `[[macro:Name]]` block (character-specific by default, `:general` on request), sees the player's macros when they mention them, and waits out combat.
- **Copy from chat (v0.9.0):** click a message to select its plain text in a read-only edit box, then Ctrl+C.
- **CLIProxyAPI support (v0.8.0):** `wai proxy` routes Claude and Codex through an API gateway with its own key and model, passed per run so the player's CLI configs stay untouched; `wai status` checks the gateway.
- **Codex support (v0.7.0):** Codex answers alongside Claude: an Agent switch in `/settings` and `wai agent`, per-chat sessions that hand the recent conversation to the new agent on a switch, and the full skill, markup, web search and UI modules through `codex exec --json`.
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
