# Changelog

## 0.9.3-nightly.10 (2026-11-05)

- Fix: replies ending in hidden markup (TikTok mode's stream reactions) left a block of blank space
  at the bottom of the card.
- The footer no longer says "Ready" when wai is idle. It only shows a status while wai is thinking,
  writing or offline.

## 0.9.3-nightly.9 (2026-11-05)

- **Settings has tabs: General, Fun and About.** The panel is about half as tall as a single
  page would be, so it fits any screen.
- **The Fun menu moved into Settings → Fun:** TikTok mode, Killstreaks (moved out of General) and
  the try-it buttons (Chopper Gunner, Nuke, +1 kill, Reset streak, Play a video, Stream chat).
- `/fun` and the separate Fun window are gone. Shift-right-click on the minimap button opens
  Settings on the Fun tab.

## 0.9.3-nightly.8 (2026-11-05)

- Fix: with settings open, your wai key (and every other key, movement included) was swallowed by
  the Toggle wai button. It now only listens while you're choosing a key.
- Closing wai with settings open brings settings back the next time you open it. Settings you
  closed stay closed.

## 0.9.3-nightly.7 (2026-11-05)

- Fix: your wai key now closes the window as well as opening it, even while you're typing in
  wai. WoW skips key bindings while a text box has the cursor, so wai watches for its own key
  there. Your draft is kept and the key isn't typed.
- The setting is now called "Toggle wai".

## 0.9.3-nightly.6 (2026-11-05)

- Fix: opening wai with your key no longer types the key into the input (Ctrl-` used to leave a
  "`"). A draft you'd left there stays as it was.

## 0.9.3-nightly.5 (2026-11-05)

- Fix: in `/settings`, the Open wai hint no longer runs under the key button. Keys read the way
  WoW writes them ("Ctrl-`" instead of "CTRL-`").

## 0.9.3-nightly.4 (2026-11-05)

- **Wowhead's Forever database is wai's primary source.** Before answering about a specific
  quest, item, NPC, drop or location, Claude and Codex check `wowhead.com/forever`. They open
  pages by ID straight from your quest log and links (`quest=62`), and use a site search when
  they only have a name. Waypoints use Wowhead's coordinates where it has them. method.gg and
  Icy Veins remain the fallback.

## 0.9.3-nightly.3 (2026-11-05)

- Settings now dock to the chat window: the panel sits beside it (on the left if the window is
  near the right edge of the screen), moves with it when you drag it, and closes with it.
  Opening settings while the chat is closed opens both.

## 0.9.3-nightly.2 (2026-11-05)

wai always knows your quests, even when General chat is busy.

- **The bridge remembers slow-changing context.** Your character, notes, talents and quest log go
  out only when they change, and the bridge adds them to every prompt. Most messages now use
  about a third of the screenshot instead of all of it.
- **Quest log with progress:** each quest has its ID and objectives ("Gnarlpine Fang: 7/15").
  After the first message only quests that changed are sent, so a ticking objective costs a line.
- **Completed quests:** your whole turned-in history reaches wai over the first few messages,
  then one quest ID per turn-in. wai can tell which quests in a zone you still have to do.
- **Each field gets a budget.** Recent chat is capped and shortened (`[General]`, long lines
  trimmed), unless you ask about chat. Error reports only use space the message doesn't need.
- If the bridge loses its memory (a reinstall), the addon notices and sends everything again.
- Fix: in `/settings`, the version and bridge status get their own lines, so a long nightly
  version no longer runs off the panel. "Not heard from this session" now reads "no messages
  yet this session".

## 0.9.3-nightly.1 (2026-11-05)

The first nightly build.

- **Pick a key to open wai** in `/settings` → Open wai: click, then press a key or combination.
  It replaces wai's previous key, says what that key used to do, and saves with your bindings.
  Esc cancels and right-click clears. It's the same binding as Key Bindings → AddOns.
- **Update tracks.** `/settings` → Updates switches between Stable and Nightly (or `wai track
  stable|nightly`). Nightly builds are GitHub prereleases with new features first. Stable updates
  and the install scripts never see them. A release always counts as newer than its own
  nightlies, so nightly players move onto it when it ships.
- Releases tagged with a suffix (`v0.9.3-nightly.1`) are published as prereleases.

## 0.9.2 (2026-11-05)

- Right-clicking a chat tab no longer closes it. It opens a small menu with Rename and Delete.
  Delete asks for a second click; on your only tab it reads "Clear chat".
- Middle-click still closes a tab, like in a browser.

## 0.9.1 (2026-11-05)

wai writes your macros.

- Ask for a macro ("make me a mouseover heal macro", "fix my Polymorph macro") and wai creates it,
  or replaces the one with that name, keeping its icon. It also deletes macros when asked.
- New macros are character-specific unless they suit every character (`/reload`, emotes); wai is
  told to prefer character macros for class spells, pets, professions and gear.
- When your message mentions macros, wai sees your current ones (the ones you name first), so it
  edits the real thing.
- Changes asked for in combat save when combat ends. Over-long names (16) or bodies (255) are
  explained instead of saved.
- Replies show each macro as a small card with its text, which you can click to copy.
- Fix: a reply that starts with a hidden title no longer opens with a blank line.
- New addon file: restart WoW (not just `/reload`) after updating.

## 0.9.0 (2026-11-05)

Copy text from the chat.

- Click any message (yours, wai's, notes or errors) to select its text, then press Ctrl+C. You can
  also drag to select just part of it. Esc, or clicking back into the input, puts the message back.
- The copy is plain text: link colours and waypoint pins drop out, and item names keep their brackets.
- Links still work as before: clicking one never starts a selection.

## 0.8.0 (2026-11-05)

CLIProxyAPI support. Both agents can send their model calls through an API gateway.

- `wai proxy on` routes Claude and Codex through [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI)
  at its default address (`http://127.0.0.1:8317`). Use `wai proxy <url>` for any other address, with
  or without `/v1`. `--key` sets the gateway's API key and `--model` picks the model both agents ask for.
  `wai proxy off` goes back to each CLI's own sign-in.
- Your own `~/.claude` and `~/.codex` configs stay as they are: wai passes the gateway to each CLI
  per run. It works for the background service too, which doesn't see your shell's environment.
- The key goes to the CLI through its environment, never on the command line, and a claude.ai login
  is never sent to the gateway.
- `wai status` checks that the gateway answers and accepts the key.

## 0.7.0 (2026-11-05)

Codex support. wai can now answer with Claude Code or OpenAI's Codex CLI.

- **Pick the agent** in `/settings` → General → Agent, or with `wai agent claude|codex` in a terminal.
  With no choice made, wai uses whichever CLI is installed (Claude first).
- **Switching mid-chat** keeps the conversation: each chat starts a new session with the new agent
  and hands it the recent messages. The bridge confirms the switch in chat, and refuses an agent
  that isn't installed.
- Codex gets everything Claude does: the wai skill on every prompt, web search, live activity
  ("Searching the web for ..."), reply markup, and UI modules (it may write only inside the addon
  folder).
- The window header says who's answering. `wai install` records where both CLIs live, and
  `wai status` checks both.
- Telemetry: a new `codex_error` event.

## 0.6.0 (2026-11-05)

Tab titles that keep up with the conversation.

- Claude names a chat with a short title ("Hunter leveling route") on its first reply, and again when
  the topic clearly changes. Background chats get retitled too.
- A name you give a tab yourself (double-click to rename) is never replaced.
- New titles fade in with a soft gold glow.
- Fix: names taken from a first message no longer end in a stray space.

## 0.5.0 (2026-11-05)

Opt-in, anonymous error reports. Off until you turn them on.

- **Consent:** wai asks once in game (Turn on / No thanks). Change it any time in `/settings` → Privacy,
  or with `wai telemetry on|off`.
- **What's sent:** an event type, a short detail with your character name, realm and home folder
  removed, the wai version, OS, client build and a random install id. Never chats or names. Full list
  in docs/TELEMETRY.md.
- **See what's sent** in Settings, and `wai telemetry show` in a terminal.
- **Collector:** `apps/telemetry`, a small Bun server that keeps only the documented fields. Point
  wai at it with `wai telemetry url <url>`; until then reports stay queued on your machine.
- Banners can now offer a second action.

## 0.4.0 (2026-11-05)

A minimap button.

- wai's portrait sits on the minimap ring. Left-click opens or closes the chat, right-click opens
  Settings, shift-right-click opens the Fun menu.
- Drag it anywhere around the ring; the spot is remembered.
- A small dot shows what wai is up to: pulsing blue while it works, gold when a reply is waiting.
- Hide it with **Minimap button** in `/settings`.

## 0.3.0 (2026-11-05)

A settings menu.

- **`/settings`** (or the new gear button in the chat header) opens a floating panel in wai's design,
  grouped into General, Windows and About.
- **Typing speed:** Instant, Fast or Normal, with a new segmented control.
- **Whisper replies:** turn off replies being posted to chat while the wai window is closed.
- **Killstreaks** on or off for this character (same switch as in `/fun`).
- **Reset window positions** puts every wai window back in its default spot.
- **About** shows the version and when the bridge was last heard from, with Check for updates and Help.
- CI uses `go-task/setup-task@v2` (Node 24).

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
